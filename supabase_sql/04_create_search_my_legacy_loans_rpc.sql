-- DAML Supabase fix: create the missing RPC used by Flutter dashboard.
-- Run this in Supabase SQL Editor.
-- It matches the logged-in user against legacy_loans using ANY of:
--   1) email
--   2) phone number
--   3) full name

create extension if not exists pgcrypto;

-- Make sure profiles exists because the Flutter app upserts into it after signup/login.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  phone text,
  role text default 'client',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.profiles enable row level security;
alter table public.legacy_loans enable row level security;

-- Helper: normalize phone numbers so +260971234567, 260971234567, 0971234567,
-- and 971234567 can match the same borrower_mobile value.
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

-- Helper: normalize names for cleaner matching.
create or replace function public.daml_normalize_name(p_name text)
returns text
language sql
immutable
as $$
  select lower(trim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')));
$$;

-- Create own-profile policies safely without duplicate-policy errors.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_select_own'
  ) then
    create policy profiles_select_own
    on public.profiles for select
    to authenticated
    using (auth.uid() = id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_insert_own'
  ) then
    create policy profiles_insert_own
    on public.profiles for insert
    to authenticated
    with check (auth.uid() = id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_update_own'
  ) then
    create policy profiles_update_own
    on public.profiles for update
    to authenticated
    using (auth.uid() = id)
    with check (auth.uid() = id);
  end if;
end $$;

-- Main RPC called by Flutter:
-- SupabaseDamlService.searchMyLegacyLoans() -> rpc('search_my_legacy_loans', {'p_limit': ...})
create or replace function public.search_my_legacy_loans(p_limit integer default 20)
returns setof public.legacy_loans
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
  v_safe_limit integer := 20;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  v_safe_limit := least(greatest(coalesce(p_limit, 20), 1), 100);

  select
    lower(coalesce(u.email, p.email, '')),
    coalesce(nullif(p.phone, ''), nullif(u.raw_user_meta_data->>'phone', ''), ''),
    coalesce(
      nullif(p.full_name, ''),
      nullif(u.raw_user_meta_data->>'full_name', ''),
      nullif(u.raw_user_meta_data->>'name', ''),
      ''
    )
  into v_email, v_phone, v_name
  from auth.users u
  left join public.profiles p on p.id = u.id
  where u.id = v_uid;

  v_norm_phone := public.daml_normalize_phone(v_phone);
  v_norm_name := public.daml_normalize_name(v_name);

  return query
  select l.*
  from public.legacy_loans l
  where
    (
      v_email <> ''
      and lower(coalesce(l.borrower_email, '')) = v_email
    )
    or
    (
      v_norm_phone <> ''
      and (
        public.daml_normalize_phone(l.borrower_mobile) = v_norm_phone
        or public.daml_normalize_phone(l.borrower_landline) = v_norm_phone
      )
    )
    or
    (
      v_norm_name <> ''
      and (
        public.daml_normalize_name(l.full_name) = v_norm_name
        or public.daml_normalize_name(concat_ws(' ', l.first_name, l.last_name)) = v_norm_name
        or public.daml_normalize_name(l.full_name) like '%' || v_norm_name || '%'
      )
    )
  order by
    case when coalesce(l.loan_status, '') ilike '%active%' then 0 else 1 end,
    coalesce(l.next_due_date, l.maturity_date, l.imported_at::date) desc nulls last
  limit v_safe_limit;
end;
$$;

revoke all on function public.search_my_legacy_loans(integer) from public;
grant execute on function public.search_my_legacy_loans(integer) to authenticated;

-- Quick test after logging in through the app is not possible in SQL Editor because auth.uid()
-- is only set for an authenticated app request. But this confirms the function exists:
select proname, pronargs
from pg_proc
where proname = 'search_my_legacy_loans';
