-- DAML loan repayments, live balance deductions and manual clearance
-- Run this in Supabase SQL Editor after 07_current_balance_and_loan_accounts.sql.
--
-- What it adds:
-- 1) Admin records repayments and current_balance is deducted safely.
-- 2) A payment that reduces balance to zero automatically marks the loan cleared.
-- 3) Admin can manually mark a loan cleared with an audit reason.
-- 4) Every payment/clearance is written to loan_transactions.
-- 5) Client receives an in-app notification after payment or clearance.
-- 6) Active legacy loans are materialized into loan_accounts the first time the client dashboard fetches them,
--    so future payments and clearance update one live source of truth.

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- Extend live loan accounts
-- -----------------------------------------------------------------------------
alter table public.loan_accounts
add column if not exists source_key text,
add column if not exists total_paid numeric default 0,
add column if not exists last_payment_at timestamptz,
add column if not exists cleared_at timestamptz;

create unique index if not exists loan_accounts_source_key_unique_idx
on public.loan_accounts (source_key)
where source_key is not null;

-- -----------------------------------------------------------------------------
-- Audit ledger for repayments and manual clearance
-- -----------------------------------------------------------------------------
create table if not exists public.loan_transactions (
  id uuid primary key default gen_random_uuid(),
  loan_account_id uuid not null references public.loan_accounts(id) on delete cascade,
  transaction_type text not null check (transaction_type in ('payment', 'manual_clearance', 'adjustment')),
  amount numeric not null default 0,
  balance_before numeric not null default 0,
  balance_after numeric not null default 0,
  reference text,
  notes text,
  recorded_by_user_id uuid references auth.users(id) on delete set null,
  recorded_by_email text,
  created_at timestamptz not null default now()
);

create index if not exists loan_transactions_account_idx
on public.loan_transactions (loan_account_id, created_at desc);

alter table public.loan_transactions enable row level security;

-- -----------------------------------------------------------------------------
-- RLS: client can read own transaction history; admins can read all.
-- Writes happen through security-definer RPCs below.
-- -----------------------------------------------------------------------------
drop policy if exists "loan transactions select own or admin" on public.loan_transactions;

create policy "loan transactions select own or admin"
on public.loan_transactions
for select
to authenticated
using (
  exists (
    select 1
    from public.loan_accounts la
    where la.id = loan_transactions.loan_account_id
      and (
        la.user_id = auth.uid()
        or lower(coalesce(la.client_email, '')) = lower(coalesce(auth.jwt() ->> 'email', ''))
      )
  )
  or exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role, '')) in ('admin', 'overall_admin', 'branch_admin')
  )
  or lower(coalesce(auth.jwt() ->> 'email', '')) = 'directaccessmoney@gmail.com'
);

-- -----------------------------------------------------------------------------
-- Helper used by admin RPCs
-- -----------------------------------------------------------------------------
create or replace function public.daml_current_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role, '')) in ('admin', 'overall_admin', 'branch_admin')
    )
    or lower(coalesce(auth.jwt() ->> 'email', '')) = 'directaccessmoney@gmail.com';
$$;

revoke all on function public.daml_current_user_is_admin() from public;
grant execute on function public.daml_current_user_is_admin() to authenticated;

-- -----------------------------------------------------------------------------
-- Admin records a repayment. Balance can never go below zero.
-- -----------------------------------------------------------------------------
create or replace function public.record_loan_payment(
  p_loan_account_id uuid,
  p_amount numeric,
  p_reference text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_actor_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_account public.loan_accounts%rowtype;
  v_before numeric := 0;
  v_after numeric := 0;
  v_target_email text := '';
  v_client_name text := 'Client';
  v_cleared boolean := false;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  if not public.daml_current_user_is_admin() then
    raise exception 'Only admin can record loan payments';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;

  select * into v_account
  from public.loan_accounts
  where id = p_loan_account_id
  for update;

  if not found then
    raise exception 'Loan account not found';
  end if;

  v_before := greatest(coalesce(v_account.current_balance, 0), 0);

  if v_before <= 0.005 then
    raise exception 'This loan is already cleared';
  end if;

  if p_amount > v_before + 0.005 then
    raise exception 'Payment amount (%) exceeds current balance (%)', p_amount, v_before;
  end if;

  v_after := greatest(v_before - p_amount, 0);
  v_cleared := v_after <= 0.005;
  if v_cleared then
    v_after := 0;
  end if;

  update public.loan_accounts
  set
    current_balance = v_after,
    total_paid = coalesce(total_paid, 0) + p_amount,
    last_payment_at = now(),
    loan_status = case when v_cleared then 'cleared' else 'active' end,
    cleared_at = case when v_cleared then now() else null end,
    updated_by_email = v_actor_email,
    updated_at = now()
  where id = p_loan_account_id;

  insert into public.loan_transactions (
    loan_account_id,
    transaction_type,
    amount,
    balance_before,
    balance_after,
    reference,
    notes,
    recorded_by_user_id,
    recorded_by_email
  ) values (
    p_loan_account_id,
    'payment',
    p_amount,
    v_before,
    v_after,
    nullif(trim(coalesce(p_reference, '')), ''),
    nullif(trim(coalesce(p_notes, '')), ''),
    v_uid,
    v_actor_email
  );

  if v_cleared and v_account.application_id is not null then
    update public.applications
    set status = 'cleared', updated_at = now()
    where id = v_account.application_id;
  end if;

  v_target_email := lower(coalesce(v_account.client_email, ''));
  v_client_name := coalesce(nullif(v_account.client_name, ''), 'Client');

  if v_target_email <> '' then
    insert into public.notifications (
      title,
      message,
      type,
      is_read,
      application_id,
      target_email,
      target_role,
      data
    ) values (
      case when v_cleared then 'Loan cleared' else 'Payment received' end,
      case when v_cleared
        then v_client_name || ', your payment of ZMW ' || to_char(p_amount, 'FM999999999990.00') || ' has cleared your loan. Your current balance is ZMW 0.00.'
        else v_client_name || ', your payment of ZMW ' || to_char(p_amount, 'FM999999999990.00') || ' has been recorded. Your new current balance is ZMW ' || to_char(v_after, 'FM999999999990.00') || '.'
      end,
      'loan_update',
      false,
      v_account.application_id,
      v_target_email,
      'client',
      jsonb_build_object(
        'loan_account_id', p_loan_account_id,
        'transaction_type', 'payment',
        'payment_amount', p_amount,
        'balance_before', v_before,
        'current_balance', v_after,
        'cleared', v_cleared
      )
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'loan_account_id', p_loan_account_id,
    'payment_amount', p_amount,
    'balance_before', v_before,
    'current_balance', v_after,
    'cleared', v_cleared
  );
end;
$$;

revoke all on function public.record_loan_payment(uuid, numeric, text, text) from public;
grant execute on function public.record_loan_payment(uuid, numeric, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Admin manually clears a loan. This is audited separately from a payment.
-- -----------------------------------------------------------------------------
create or replace function public.clear_loan_account(
  p_loan_account_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_actor_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_account public.loan_accounts%rowtype;
  v_before numeric := 0;
  v_target_email text := '';
  v_client_name text := 'Client';
  v_reason text := coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'Marked cleared by admin');
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  if not public.daml_current_user_is_admin() then
    raise exception 'Only admin can clear a loan';
  end if;

  select * into v_account
  from public.loan_accounts
  where id = p_loan_account_id
  for update;

  if not found then
    raise exception 'Loan account not found';
  end if;

  v_before := greatest(coalesce(v_account.current_balance, 0), 0);

  update public.loan_accounts
  set
    current_balance = 0,
    loan_status = 'cleared',
    cleared_at = coalesce(cleared_at, now()),
    updated_by_email = v_actor_email,
    updated_at = now(),
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'clearance_reason', v_reason,
      'cleared_by_email', v_actor_email,
      'cleared_at', now()
    )
  where id = p_loan_account_id;

  insert into public.loan_transactions (
    loan_account_id,
    transaction_type,
    amount,
    balance_before,
    balance_after,
    reference,
    notes,
    recorded_by_user_id,
    recorded_by_email
  ) values (
    p_loan_account_id,
    'manual_clearance',
    0,
    v_before,
    0,
    null,
    v_reason,
    v_uid,
    v_actor_email
  );

  if v_account.application_id is not null then
    update public.applications
    set status = 'cleared', updated_at = now()
    where id = v_account.application_id;
  end if;

  v_target_email := lower(coalesce(v_account.client_email, ''));
  v_client_name := coalesce(nullif(v_account.client_name, ''), 'Client');

  if v_target_email <> '' then
    insert into public.notifications (
      title,
      message,
      type,
      is_read,
      application_id,
      target_email,
      target_role,
      data
    ) values (
      'Loan cleared',
      v_client_name || ', your loan has been marked cleared. Your current balance is ZMW 0.00.',
      'loan_update',
      false,
      v_account.application_id,
      v_target_email,
      'client',
      jsonb_build_object(
        'loan_account_id', p_loan_account_id,
        'transaction_type', 'manual_clearance',
        'balance_before', v_before,
        'current_balance', 0,
        'reason', v_reason,
        'cleared', true
      )
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'loan_account_id', p_loan_account_id,
    'balance_before', v_before,
    'current_balance', 0,
    'cleared', true,
    'reason', v_reason
  );
end;
$$;

revoke all on function public.clear_loan_account(uuid, text) from public;
grant execute on function public.clear_loan_account(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Replace dashboard RPC.
-- Key change: first matching active legacy data is copied into loan_accounts once.
-- After that, repayments/clearance update loan_accounts and legacy history can no longer
-- bring an old balance back onto the dashboard.
-- -----------------------------------------------------------------------------
create or replace function public.get_my_current_loan_summary(p_include_loans boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := '';
  v_phone text := '';
  v_name text := '';
  v_norm_phone text := '';
  v_norm_name text := '';
  v_existing_live_count integer := 0;
  v_legacy_sync_count integer := 0;
  v_legacy_sync_principal numeric := 0;
  v_legacy_sync_balance numeric := 0;
  v_legacy_sync_next_due numeric := 0;
  v_legacy_sync_next_date date;
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select
    lower(coalesce(u.email, p.email, '')),
    coalesce(nullif(p.phone, ''), nullif(u.raw_user_meta_data->>'phone', ''), ''),
    coalesce(nullif(p.full_name, ''), nullif(u.raw_user_meta_data->>'full_name', ''), nullif(u.raw_user_meta_data->>'name', ''), '')
  into v_email, v_phone, v_name
  from auth.users u
  left join public.profiles p on p.id = u.id
  where u.id = v_uid;

  v_norm_phone := public.daml_normalize_phone(v_phone);
  v_norm_name := public.daml_normalize_name(v_name);

  select count(*) into v_existing_live_count
  from public.loan_accounts la
  where
    (
      la.user_id = v_uid
      or (v_email <> '' and lower(coalesce(la.client_email, '')) = v_email)
      or (v_norm_phone <> '' and public.daml_normalize_phone(la.client_phone) = v_norm_phone)
    )
    and lower(coalesce(la.loan_status, '')) not in ('rejected', 'cancelled', 'canceled');

  -- First dashboard fetch for a legacy client: create one manageable live account.
  if v_existing_live_count = 0 then
    with matched as (
      select
        coalesce(l.principal_amount, 0) as principal_amount,
        public.daml_legacy_current_balance(
          l.loan_status,
          l.balance_amount,
          l.pending_due,
          l.pending_principal_due,
          l.pending_interest_due,
          l.pending_penalty_due,
          l.pending_fees_due,
          l.amortization_due,
          l.total_interest_balance,
          l.penalty_amount
        ) as current_balance,
        coalesce(l.next_installment_amount, l.previous_installment_amount, 0) as next_due_amount,
        coalesce(l.next_due_date, l.next_installment_date, l.maturity_date) as next_due_date
      from public.legacy_loans l
      where
        (v_email <> '' and lower(coalesce(l.borrower_email, '')) = v_email)
        or (v_norm_phone <> '' and (
          public.daml_normalize_phone(l.borrower_mobile) = v_norm_phone
          or public.daml_normalize_phone(l.borrower_landline) = v_norm_phone
        ))
        or (v_norm_name <> '' and (
          public.daml_normalize_name(l.full_name) = v_norm_name
          or public.daml_normalize_name(concat_ws(' ', l.first_name, l.last_name)) = v_norm_name
          or public.daml_normalize_name(l.full_name) like '%' || v_norm_name || '%'
        ))
    ), current_rows as (
      select * from matched where current_balance > 0
    )
    select
      count(*)::int,
      coalesce(sum(principal_amount), 0),
      coalesce(sum(current_balance), 0),
      coalesce((array_agg(next_due_amount order by next_due_date nulls last))[1], 0),
      min(next_due_date) filter (where next_due_date is not null)
    into
      v_legacy_sync_count,
      v_legacy_sync_principal,
      v_legacy_sync_balance,
      v_legacy_sync_next_due,
      v_legacy_sync_next_date
    from current_rows;

    if v_legacy_sync_count > 0 and v_legacy_sync_balance > 0 then
      insert into public.loan_accounts (
        user_id,
        client_name,
        client_email,
        client_phone,
        source,
        source_key,
        principal_amount,
        current_balance,
        next_due_amount,
        next_due_date,
        loan_status,
        metadata,
        updated_at
      ) values (
        v_uid,
        v_name,
        v_email,
        v_norm_phone,
        'legacy_sync',
        'legacy_user:' || v_uid::text,
        v_legacy_sync_principal,
        v_legacy_sync_balance,
        v_legacy_sync_next_due,
        v_legacy_sync_next_date,
        'active',
        jsonb_build_object(
          'materialized_from', 'legacy_loans',
          'matched_legacy_rows', v_legacy_sync_count,
          'materialized_at', now()
        ),
        now()
      )
      on conflict (source_key) where source_key is not null
      do nothing;
    end if;
  end if;

  with live_all as (
    select
      la.id::text as id,
      coalesce(la.client_name, v_name) as full_name,
      la.client_email as borrower_email,
      la.client_phone as borrower_mobile,
      coalesce(la.loan_status, 'active') as loan_status,
      coalesce(la.principal_amount, 0) as principal_amount,
      greatest(coalesce(la.current_balance, 0), 0) as current_balance,
      coalesce(la.next_due_amount, 0) as next_installment_amount,
      la.next_due_date,
      la.source,
      la.updated_at,
      la.application_id::text as application_id
    from public.loan_accounts la
    where
      (
        la.user_id = v_uid
        or (v_email <> '' and lower(coalesce(la.client_email, '')) = v_email)
        or (v_norm_phone <> '' and public.daml_normalize_phone(la.client_phone) = v_norm_phone)
      )
      and lower(coalesce(la.loan_status, '')) not in ('rejected', 'cancelled', 'canceled')
  ),
  live_current as (
    select * from live_all
    where current_balance > 0.005
      and not public.daml_status_is_cleared(loan_status)
  ),
  legacy_matched as (
    select
      l.id::text as id,
      coalesce(l.full_name, concat_ws(' ', l.first_name, l.last_name), v_name) as full_name,
      l.borrower_email,
      l.borrower_mobile,
      coalesce(l.loan_status, 'legacy') as loan_status,
      coalesce(l.principal_amount, 0) as principal_amount,
      public.daml_legacy_current_balance(
        l.loan_status,
        l.balance_amount,
        l.pending_due,
        l.pending_principal_due,
        l.pending_interest_due,
        l.pending_penalty_due,
        l.pending_fees_due,
        l.amortization_due,
        l.total_interest_balance,
        l.penalty_amount
      ) as current_balance,
      coalesce(l.next_installment_amount, l.previous_installment_amount, 0) as next_installment_amount,
      coalesce(l.next_due_date, l.next_installment_date, l.maturity_date) as next_due_date,
      'legacy_loans'::text as source,
      coalesce(l.imported_at, now()) as updated_at,
      null::text as application_id
    from public.legacy_loans l
    where
      (v_email <> '' and lower(coalesce(l.borrower_email, '')) = v_email)
      or (v_norm_phone <> '' and (
        public.daml_normalize_phone(l.borrower_mobile) = v_norm_phone
        or public.daml_normalize_phone(l.borrower_landline) = v_norm_phone
      ))
      or (v_norm_name <> '' and (
        public.daml_normalize_name(l.full_name) = v_norm_name
        or public.daml_normalize_name(concat_ws(' ', l.first_name, l.last_name)) = v_norm_name
        or public.daml_normalize_name(l.full_name) like '%' || v_norm_name || '%'
      ))
  ),
  legacy_current as (
    select * from legacy_matched where current_balance > 0.005
  ),
  counts as (
    select
      (select count(*) from live_all)::int as live_all_count,
      (select count(*) from live_current)::int as live_current_count,
      (select count(*) from legacy_matched)::int as legacy_matched_count,
      (select count(*) from legacy_current)::int as legacy_current_count
  ),
  chosen as (
    -- Any live account history becomes the source of truth. Only positive active rows
    -- contribute to Borrowed and Current Balance.
    select * from live_current where (select live_all_count from counts) > 0
    union all
    select * from legacy_current where (select live_all_count from counts) = 0
  ),
  summary as (
    select
      coalesce(sum(principal_amount), 0) as total_borrowed,
      coalesce(sum(current_balance), 0) as total_balance,
      count(*)::int as loan_count,
      min(next_due_date) filter (where next_due_date is not null) as next_due_date,
      coalesce((array_agg(next_installment_amount order by next_due_date nulls last))[1], 0) as next_due_amount,
      max(updated_at) as last_updated
    from chosen
  )
  select jsonb_build_object(
    'success', true,
    'source', case
      when c.live_all_count > 0 then 'loan_accounts'
      when c.legacy_current_count > 0 then 'legacy_loans'
      else 'none'
    end,
    'client', jsonb_build_object(
      'clientKey', case when v_email <> '' then 'email:' || v_email else 'phone:' || v_norm_phone end,
      'fullName', coalesce((select full_name from chosen where trim(coalesce(full_name, '')) <> '' order by updated_at desc limit 1), v_name),
      'email', v_email,
      'phone', v_phone,
      'balance', coalesce(s.total_balance, 0),
      'loanStatus', case
        when coalesce(s.total_balance, 0) > 0.005 then 'Active'
        when c.live_all_count > 0 or c.legacy_matched_count > 0 then 'Cleared'
        else 'No Loans'
      end,
      'statusBucket', case when coalesce(s.total_balance, 0) > 0.005 then 'balance' else 'cleared' end,
      'isExtended', false,
      'updatedAt', coalesce(s.last_updated, now())
    ),
    'loansSummary', jsonb_build_object(
      'loanCount', coalesce(s.loan_count, 0),
      'totalBorrowed', case when coalesce(s.total_balance, 0) > 0.005 then coalesce(s.total_borrowed, 0) else 0 end,
      'totalBalance', coalesce(s.total_balance, 0),
      'nextDueDate', s.next_due_date,
      'nextDueAmount', coalesce(s.next_due_amount, 0),
      'source', case
        when c.live_all_count > 0 then 'loan_accounts'
        when c.legacy_current_count > 0 then 'legacy_loans'
        else 'none'
      end,
      'pastLoanCount', greatest(c.legacy_matched_count - c.legacy_current_count, 0)
    ),
    'loans', case when p_include_loans then coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', id,
          '_id', id,
          'fullName', full_name,
          'borrowerEmail', borrower_email,
          'borrowerMobile', borrower_mobile,
          'loanStatus', loan_status,
          'principalAmount', principal_amount,
          'currentBalance', current_balance,
          'balanceAmount', current_balance,
          'amortizationDue', current_balance,
          'totalInterestBalance', 0,
          'penaltyAmount', 0,
          'nextInstallmentAmount', next_installment_amount,
          'nextDueDate', next_due_date,
          'branchId', source,
          'source', source,
          'applicationId', application_id,
          'updatedAt', updated_at
        ) order by updated_at desc
      ) from chosen
    ), '[]'::jsonb) else '[]'::jsonb end
  ) into v_result
  from counts c cross join summary s;

  return v_result;
end;
$$;

revoke all on function public.get_my_current_loan_summary(boolean) from public;
grant execute on function public.get_my_current_loan_summary(boolean) to authenticated;

notify pgrst, 'reload schema';
