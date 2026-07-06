-- DAML current-balance dashboard + loan account updates
-- Run this in Supabase SQL Editor after applying the Flutter patch.
-- Purpose:
-- 1) Keep past/cleared legacy loans from showing as current debt.
-- 2) Store approved/confirmed applications as live loan account records.
-- 3) Let the client dashboard show one current balance: K 0 if cleared, balance if active.

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- Required application columns used by the admin approval flow
-- -----------------------------------------------------------------------------
alter table public.applications
add column if not exists updated_at timestamptz default now(),
add column if not exists handled_at timestamptz,
add column if not exists confirmed_at timestamptz,
add column if not exists approved_at timestamptz;

alter table public.notifications
add column if not exists target_email text,
add column if not exists target_role text default 'client',
add column if not exists data jsonb default '{}'::jsonb;

-- -----------------------------------------------------------------------------
-- Live/current loan account table. This is the table the dashboard should trust
-- for newly approved loans.
-- -----------------------------------------------------------------------------
create table if not exists public.loan_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  application_id uuid references public.applications(id) on delete set null,
  client_name text,
  client_email text,
  client_phone text,
  source text default 'application',
  loan_number text,
  principal_amount numeric default 0,
  current_balance numeric default 0,
  next_due_amount numeric default 0,
  next_due_date date,
  loan_status text default 'active',
  approved_at timestamptz,
  handled_at timestamptz,
  updated_by_email text,
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists loan_accounts_user_id_idx on public.loan_accounts (user_id);
create index if not exists loan_accounts_email_idx on public.loan_accounts (lower(client_email));
create index if not exists loan_accounts_phone_idx on public.loan_accounts (client_phone);
create index if not exists loan_accounts_application_idx on public.loan_accounts (application_id);
create index if not exists loan_accounts_updated_idx on public.loan_accounts (updated_at desc);

-- Add a unique application link safely for upsert support.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'loan_accounts_application_id_unique'
      and conrelid = 'public.loan_accounts'::regclass
  ) then
    alter table public.loan_accounts
    add constraint loan_accounts_application_id_unique unique (application_id);
  end if;
end $$;

alter table public.loan_accounts enable row level security;

-- -----------------------------------------------------------------------------
-- Helper functions
-- -----------------------------------------------------------------------------
create or replace function public.daml_normalize_phone(p_phone text)
returns text
language sql
immutable
as $$
  with digits as (
    select regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g') as d
  )
  select case
    when d = '' then ''
    when d like '260%' and length(d) >= 12 then '0' || substring(d from 4)
    when d like '0260%' and length(d) >= 13 then '0' || substring(d from 5)
    when length(d) = 9 then '0' || d
    else d
  end
  from digits;
$$;

create or replace function public.daml_normalize_name(p_name text)
returns text
language sql
immutable
as $$
  select lower(trim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')));
$$;

create or replace function public.daml_parse_money(p_text text)
returns numeric
language plpgsql
immutable
as $$
declare
  v text;
begin
  v := regexp_replace(coalesce(p_text, ''), '[^0-9.-]', '', 'g');
  if v is null or trim(v) = '' or trim(v) = '-' or trim(v) = '.' then
    return 0;
  end if;
  return v::numeric;
exception when others then
  return 0;
end;
$$;

create or replace function public.daml_parse_date(p_text text)
returns date
language plpgsql
immutable
as $$
begin
  if p_text is null or trim(p_text) = '' then
    return null;
  end if;
  return p_text::date;
exception when others then
  return null;
end;
$$;

create or replace function public.daml_status_is_cleared(p_status text)
returns boolean
language sql
immutable
as $$
  select lower(coalesce(p_status, '')) like '%fully paid%'
      or lower(coalesce(p_status, '')) like '%cleared%'
      or lower(coalesce(p_status, '')) like '%closed%'
      or lower(coalesce(p_status, '')) like '%paid off%'
      or lower(coalesce(p_status, '')) like '%write-off%'
      or lower(coalesce(p_status, '')) like '%written off%'
      or lower(coalesce(p_status, '')) like '%cancelled%'
      or lower(coalesce(p_status, '')) like '%canceled%';
$$;

create or replace function public.daml_legacy_current_balance(
  p_loan_status text,
  p_balance_amount numeric,
  p_pending_due numeric,
  p_pending_principal_due numeric,
  p_pending_interest_due numeric,
  p_pending_penalty_due numeric,
  p_pending_fees_due numeric,
  p_amortization_due numeric,
  p_total_interest_balance numeric,
  p_penalty_amount numeric
)
returns numeric
language sql
immutable
as $$
  select case
    when public.daml_status_is_cleared(p_loan_status) then 0
    when coalesce(p_balance_amount, 0) > 0 then greatest(coalesce(p_balance_amount, 0), 0)
    when coalesce(p_pending_due, 0) > 0 then greatest(coalesce(p_pending_due, 0), 0)
    when coalesce(p_pending_principal_due, 0)
       + coalesce(p_pending_interest_due, 0)
       + coalesce(p_pending_penalty_due, 0)
       + coalesce(p_pending_fees_due, 0) > 0
      then greatest(
        coalesce(p_pending_principal_due, 0)
        + coalesce(p_pending_interest_due, 0)
        + coalesce(p_pending_penalty_due, 0)
        + coalesce(p_pending_fees_due, 0),
        0
      )
    when coalesce(p_amortization_due, 0)
       + coalesce(p_total_interest_balance, 0)
       + coalesce(p_penalty_amount, 0) > 0
      then greatest(
        coalesce(p_amortization_due, 0)
        + coalesce(p_total_interest_balance, 0)
        + coalesce(p_penalty_amount, 0),
        0
      )
    else 0
  end;
$$;

-- -----------------------------------------------------------------------------
-- Policies
-- -----------------------------------------------------------------------------
drop policy if exists "loan accounts select own or admin" on public.loan_accounts;
drop policy if exists "loan accounts admin insert" on public.loan_accounts;
drop policy if exists "loan accounts admin update" on public.loan_accounts;

create policy "loan accounts select own or admin"
on public.loan_accounts
for select
to authenticated
using (
  user_id = auth.uid()
  or lower(coalesce(client_email, '')) = lower(coalesce(auth.jwt() ->> 'email', ''))
  or exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role, '')) in ('admin', 'overall_admin', 'branch_admin')
  )
  or lower(coalesce(auth.jwt() ->> 'email', '')) = 'directaccessmoney@gmail.com'
);

create policy "loan accounts admin insert"
on public.loan_accounts
for insert
to authenticated
with check (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role, '')) in ('admin', 'overall_admin', 'branch_admin')
  )
  or lower(coalesce(auth.jwt() ->> 'email', '')) = 'directaccessmoney@gmail.com'
);

create policy "loan accounts admin update"
on public.loan_accounts
for update
to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role, '')) in ('admin', 'overall_admin', 'branch_admin')
  )
  or lower(coalesce(auth.jwt() ->> 'email', '')) = 'directaccessmoney@gmail.com'
)
with check (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role, '')) in ('admin', 'overall_admin', 'branch_admin')
  )
  or lower(coalesce(auth.jwt() ->> 'email', '')) = 'directaccessmoney@gmail.com'
);

-- Ensure applications/notifications still allow the app workflows.
alter table public.applications enable row level security;
alter table public.notifications enable row level security;

-- -----------------------------------------------------------------------------
-- Client dashboard RPC: returns one current balance and only active/current loans.
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
  v_live_count integer := 0;
  v_legacy_matched_count integer := 0;
  v_legacy_current_count integer := 0;
  v_client_name text := '';
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

  with live as (
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
      (
        v_email <> '' and lower(coalesce(l.borrower_email, '')) = v_email
      )
      or
      (
        v_norm_phone <> '' and (
          public.daml_normalize_phone(l.borrower_mobile) = v_norm_phone
          or public.daml_normalize_phone(l.borrower_landline) = v_norm_phone
        )
      )
      or
      (
        v_norm_name <> '' and (
          public.daml_normalize_name(l.full_name) = v_norm_name
          or public.daml_normalize_name(concat_ws(' ', l.first_name, l.last_name)) = v_norm_name
          or public.daml_normalize_name(l.full_name) like '%' || v_norm_name || '%'
        )
      )
  ),
  legacy_current as (
    select * from legacy_matched where current_balance > 0
  ),
  counts as (
    select
      (select count(*) from live) as live_count,
      (select count(*) from legacy_matched) as legacy_matched_count,
      (select count(*) from legacy_current) as legacy_current_count
  ),
  chosen as (
    -- Live loan_accounts win over legacy data once admin confirms/approves a new loan.
    select * from live where (select live_count from counts) > 0
    union all
    select * from legacy_current where (select live_count from counts) = 0
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
  select
    c.live_count,
    c.legacy_matched_count,
    c.legacy_current_count,
    coalesce((select full_name from chosen where full_name is not null and trim(full_name) <> '' order by updated_at desc limit 1), v_name),
    jsonb_build_object(
      'success', true,
      'source', case when c.live_count > 0 then 'loan_accounts' when c.legacy_current_count > 0 then 'legacy_loans' else 'none' end,
      'client', jsonb_build_object(
        'clientKey', case when v_email <> '' then 'email:' || v_email else 'phone:' || v_norm_phone end,
        'fullName', coalesce((select full_name from chosen where full_name is not null and trim(full_name) <> '' order by updated_at desc limit 1), v_name),
        'email', v_email,
        'phone', v_phone,
        'balance', coalesce(s.total_balance, 0),
        'loanStatus', case
          when coalesce(s.total_balance, 0) > 0 then 'Active'
          when c.legacy_matched_count > 0 or c.live_count > 0 then 'Cleared'
          else 'No Loans'
        end,
        'statusBucket', case when coalesce(s.total_balance, 0) > 0 then 'balance' else 'cleared' end,
        'isExtended', false,
        'updatedAt', coalesce(s.last_updated, now())
      ),
      'loansSummary', jsonb_build_object(
        'loanCount', coalesce(s.loan_count, 0),
        'totalBorrowed', coalesce(s.total_borrowed, 0),
        'totalBalance', coalesce(s.total_balance, 0),
        'nextDueDate', s.next_due_date,
        'nextDueAmount', coalesce(s.next_due_amount, 0),
        'source', case when c.live_count > 0 then 'loan_accounts' when c.legacy_current_count > 0 then 'legacy_loans' else 'none' end,
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
        )
        from chosen
      ), '[]'::jsonb) else '[]'::jsonb end
    )
  into v_live_count, v_legacy_matched_count, v_legacy_current_count, v_client_name, v_result
  from counts c cross join summary s;

  return v_result;
end;
$$;

revoke all on function public.get_my_current_loan_summary(boolean) from public;
grant execute on function public.get_my_current_loan_summary(boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- Admin RPC: update application status, create/update loan account on approval,
-- and notify the client. The Flutter admin Confirm button calls this.
-- -----------------------------------------------------------------------------
create or replace function public.confirm_application_and_update_loan_account(
  p_application_id uuid,
  p_status text default 'confirmed'
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_actor_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_is_admin boolean := false;
  v_app public.applications%rowtype;
  v_form jsonb := '{}'::jsonb;
  v_status text := lower(coalesce(p_status, 'handled'));
  v_loan_amount numeric := 0;
  v_installment numeric := 0;
  v_next_due date;
  v_account_id uuid;
  v_client_name text := '';
  v_target_email text := '';
  v_phone text := '';
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select exists (
    select 1 from public.profiles p
    where p.id = v_uid
      and lower(coalesce(p.role, '')) in ('admin', 'overall_admin', 'branch_admin')
  ) or v_actor_email = 'directaccessmoney@gmail.com'
  into v_is_admin;

  if not v_is_admin then
    raise exception 'Only admin can update application status';
  end if;

  select * into v_app
  from public.applications
  where id = p_application_id;

  if not found then
    raise exception 'Application not found';
  end if;

  v_form := coalesce(v_app.form_data, '{}'::jsonb);
  v_client_name := coalesce(nullif(v_app.client_name, ''), nullif(v_form->>'name', ''), 'Client');
  v_target_email := lower(coalesce(v_app.submitted_by_email, ''));
  v_phone := public.daml_normalize_phone(coalesce(v_app.phone, v_form->>'mobile', ''));
  v_loan_amount := coalesce(v_app.loan_amount, public.daml_parse_money(v_form->>'loanAmount'), 0);
  v_installment := public.daml_parse_money(v_form->>'monthlyInstallment');
  v_next_due := coalesce(public.daml_parse_date(v_form->>'loanEnd'), public.daml_parse_date(v_form->>'nextDueDate'));

  update public.applications
  set
    status = p_status,
    handled_at = case when v_status in ('handled', 'confirmed', 'approved') then now() else handled_at end,
    confirmed_at = case when v_status in ('confirmed', 'approved') then now() else confirmed_at end,
    approved_at = case when v_status in ('confirmed', 'approved') then now() else approved_at end,
    updated_at = now()
  where id = p_application_id;

  if v_status in ('confirmed', 'approved') then
    update public.loan_accounts
    set
      user_id = v_app.submitted_by_user_id,
      client_name = v_client_name,
      client_email = v_target_email,
      client_phone = v_phone,
      source = 'application',
      principal_amount = v_loan_amount,
      current_balance = v_loan_amount,
      next_due_amount = v_installment,
      next_due_date = v_next_due,
      loan_status = 'active',
      approved_at = coalesce(approved_at, now()),
      updated_by_email = v_actor_email,
      metadata = jsonb_build_object(
        'application_id', p_application_id,
        'form_data', v_form,
        'pdf_path', v_app.pdf_path,
        'pdf_filename', v_app.pdf_filename,
        'approved_from_status', p_status
      ),
      updated_at = now()
    where application_id = p_application_id
    returning id into v_account_id;

    if v_account_id is null then
      insert into public.loan_accounts (
        user_id,
        application_id,
        client_name,
        client_email,
        client_phone,
        source,
        principal_amount,
        current_balance,
        next_due_amount,
        next_due_date,
        loan_status,
        approved_at,
        updated_by_email,
        metadata
      ) values (
        v_app.submitted_by_user_id,
        p_application_id,
        v_client_name,
        v_target_email,
        v_phone,
        'application',
        v_loan_amount,
        v_loan_amount,
        v_installment,
        v_next_due,
        'active',
        now(),
        v_actor_email,
        jsonb_build_object(
          'application_id', p_application_id,
          'form_data', v_form,
          'pdf_path', v_app.pdf_path,
          'pdf_filename', v_app.pdf_filename,
          'approved_from_status', p_status
        )
      ) returning id into v_account_id;
    end if;
  end if;

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
      case when v_status in ('confirmed', 'approved') then 'Loan approved' else 'Application handled' end,
      case when v_status in ('confirmed', 'approved')
        then v_client_name || ', your loan has been approved. Your current balance is now K ' || to_char(v_loan_amount, 'FM999999999990.00') || '.'
        else v_client_name || ', your loan application has been received and handled by Direct Access Money Lending.'
      end,
      case when v_status in ('confirmed', 'approved') then 'loan_update' else 'success' end,
      false,
      p_application_id,
      v_target_email,
      'client',
      jsonb_build_object(
        'application_id', p_application_id,
        'status', p_status,
        'loan_account_id', v_account_id,
        'current_balance', case when v_status in ('confirmed', 'approved') then v_loan_amount else null end,
        'pdf_path', v_app.pdf_path,
        'pdf_filename', v_app.pdf_filename
      )
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'status', p_status,
    'loan_account_id', v_account_id,
    'current_balance', case when v_status in ('confirmed', 'approved') then v_loan_amount else null end
  );
end;
$$;

revoke all on function public.confirm_application_and_update_loan_account(uuid, text) from public;
grant execute on function public.confirm_application_and_update_loan_account(uuid, text) to authenticated;

notify pgrst, 'reload schema';
