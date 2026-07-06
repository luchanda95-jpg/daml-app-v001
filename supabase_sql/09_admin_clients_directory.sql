-- DAML: database-backed Clients tab for Overall Admin
-- Run this in Supabase SQL Editor after the previous Supabase migration SQL files.
--
-- The admin Clients tab will read client identity records from:
--   1) profiles       -> users who signed up in the app
--   2) loan_accounts  -> live/current loan accounts
--   3) legacy_loans   -> imported MongoDB/CSV borrower records
--
-- Flutter then merges duplicates when ANY of email, phone, or full name matches.

create extension if not exists pgcrypto;

-- These helpers are safe to recreate and match the normalisation already used by DAML.
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

-- A standalone admin check so this SQL remains usable even if older helper names changed.
create or replace function public.daml_can_view_client_directory()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    lower(coalesce(auth.jwt() ->> 'email', '')) = 'directaccessmoney@gmail.com'
    or exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role, '')) in ('ovadmin', 'overall_admin', 'admin')
    );
$$;

revoke all on function public.daml_can_view_client_directory() from public;
grant execute on function public.daml_can_view_client_directory() to authenticated;

create or replace function public.admin_client_directory(
  p_query text default null,
  p_limit integer default 10000
)
returns table (
  client_key text,
  full_name text,
  phone text,
  email text,
  source text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_q text := lower(trim(coalesce(p_query, '')));
  v_limit integer := least(greatest(coalesce(p_limit, 10000), 1), 10000);
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not public.daml_can_view_client_directory() then
    raise exception 'Only overall admin can view the client directory';
  end if;

  return query
  with profile_rows as (
    select
      'profile:' || p.id::text as client_key,
      nullif(trim(coalesce(p.full_name, '')), '') as full_name,
      nullif(trim(coalesce(p.phone, '')), '') as phone,
      nullif(lower(trim(coalesce(p.email, ''))), '') as email,
      'profile'::text as source,
      coalesce(p.updated_at, p.created_at, now()) as updated_at
    from public.profiles p
    where lower(coalesce(p.email, '')) <> 'directaccessmoney@gmail.com'
      and lower(coalesce(p.role, 'client')) not in ('ovadmin', 'overall_admin', 'admin', 'branch_admin')
  ),
  live_rows as (
    select
      'live:' || la.id::text as client_key,
      nullif(trim(coalesce(la.client_name, '')), '') as full_name,
      nullif(trim(coalesce(la.client_phone, '')), '') as phone,
      nullif(lower(trim(coalesce(la.client_email, ''))), '') as email,
      'loan_account'::text as source,
      coalesce(la.updated_at, la.created_at, now()) as updated_at
    from public.loan_accounts la
  ),
  legacy_rows as (
    select
      'legacy:' || encode(
        digest(
          coalesce(nullif(lower(trim(l.borrower_email)), ''), '') || '|' ||
          public.daml_normalize_phone(l.borrower_mobile) || '|' ||
          public.daml_normalize_name(l.full_name),
          'sha256'
        ),
        'hex'
      ) as client_key,
      max(nullif(trim(coalesce(l.full_name, '')), '')) as full_name,
      max(nullif(trim(coalesce(l.borrower_mobile, '')), '')) as phone,
      max(nullif(lower(trim(coalesce(l.borrower_email, ''))), '')) as email,
      'legacy'::text as source,
      max(coalesce(l.imported_at, now())) as updated_at
    from public.legacy_loans l
    where nullif(trim(coalesce(l.full_name, '')), '') is not null
       or nullif(trim(coalesce(l.borrower_mobile, '')), '') is not null
       or nullif(trim(coalesce(l.borrower_email, '')), '') is not null
    group by
      coalesce(nullif(lower(trim(l.borrower_email)), ''), ''),
      public.daml_normalize_phone(l.borrower_mobile),
      public.daml_normalize_name(l.full_name)
  ),
  all_rows as (
    select * from profile_rows
    union all
    select * from live_rows
    union all
    select * from legacy_rows
  )
  select
    a.client_key,
    a.full_name,
    a.phone,
    a.email,
    a.source,
    a.updated_at
  from all_rows a
  where
    v_q = ''
    or lower(coalesce(a.full_name, '')) like '%' || v_q || '%'
    or lower(coalesce(a.phone, '')) like '%' || v_q || '%'
    or lower(coalesce(a.email, '')) like '%' || v_q || '%'
  order by
    coalesce(nullif(lower(a.full_name), ''), nullif(lower(a.email), ''), lower(a.phone), '') asc,
    a.updated_at desc
  limit v_limit;
end;
$$;

revoke all on function public.admin_client_directory(text, integer) from public;
grant execute on function public.admin_client_directory(text, integer) to authenticated;

notify pgrst, 'reload schema';

-- Verification: this confirms the RPC exists.
select proname, pronargs
from pg_proc
where proname = 'admin_client_directory';
