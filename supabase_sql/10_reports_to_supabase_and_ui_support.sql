-- DAML: move daily/monthly reporting, branch comments and Zanaco distributions
-- from Render/MongoDB to Supabase.
-- Run this entire file in Supabase SQL Editor before testing the patch.

create extension if not exists pgcrypto with schema extensions;

alter table if exists public.profiles
  add column if not exists branch text;

-- ---------------------------------------------------------------------------
-- Role helpers used by RLS
-- ---------------------------------------------------------------------------
create or replace function public.daml_current_role()
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select lower(coalesce(
    (select p.role from public.profiles p where p.id = auth.uid()),
    (select u.raw_user_meta_data->>'role' from auth.users u where u.id = auth.uid()),
    ''
  ));
$$;

create or replace function public.daml_current_branch()
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select lower(trim(coalesce(
    (select p.branch from public.profiles p where p.id = auth.uid()),
    (select u.raw_user_meta_data->>'branch' from auth.users u where u.id = auth.uid()),
    ''
  )));
$$;

create or replace function public.daml_is_overall_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select public.daml_current_role() in ('ovadmin', 'overall_admin', 'overall admin');
$$;

create or replace function public.daml_is_branch_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select public.daml_current_role() in ('branch_admin', 'branch admin', 'branch');
$$;

revoke all on function public.daml_current_role() from public;
revoke all on function public.daml_current_branch() from public;
revoke all on function public.daml_is_overall_admin() from public;
revoke all on function public.daml_is_branch_admin() from public;
grant execute on function public.daml_current_role() to authenticated;
grant execute on function public.daml_current_branch() to authenticated;
grant execute on function public.daml_is_overall_admin() to authenticated;
grant execute on function public.daml_is_branch_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- Daily reports
-- ---------------------------------------------------------------------------
create table if not exists public.daily_reports (
  id uuid primary key default gen_random_uuid(),
  branch text not null,
  report_date date not null,
  opening_balances jsonb not null default '{}'::jsonb,
  loan_counts jsonb not null default '{}'::jsonb,
  closing_balances jsonb not null default '{}'::jsonb,
  total_disbursed numeric not null default 0,
  total_collected numeric not null default 0,
  collected_for_other_branches numeric not null default 0,
  petty_cash numeric not null default 0,
  expenses numeric not null default 0,
  zanaco_applied jsonb not null default '{}'::jsonb,
  total_loans integer not null default 0,
  submitted_by uuid references auth.users(id) on delete set null,
  submitted_email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch, report_date)
);

create index if not exists daily_reports_branch_date_idx
  on public.daily_reports (branch, report_date desc);

alter table public.daily_reports enable row level security;

drop policy if exists daily_reports_select on public.daily_reports;
drop policy if exists daily_reports_insert on public.daily_reports;
drop policy if exists daily_reports_update on public.daily_reports;
drop policy if exists daily_reports_delete on public.daily_reports;

create policy daily_reports_select
on public.daily_reports for select to authenticated
using (
  public.daml_is_overall_admin()
  or (public.daml_is_branch_admin() and lower(trim(branch)) = public.daml_current_branch())
);

create policy daily_reports_insert
on public.daily_reports for insert to authenticated
with check (
  public.daml_is_overall_admin()
  or (public.daml_is_branch_admin() and lower(trim(branch)) = public.daml_current_branch())
);

create policy daily_reports_update
on public.daily_reports for update to authenticated
using (
  public.daml_is_overall_admin()
  or (public.daml_is_branch_admin() and lower(trim(branch)) = public.daml_current_branch())
)
with check (
  public.daml_is_overall_admin()
  or (public.daml_is_branch_admin() and lower(trim(branch)) = public.daml_current_branch())
);

create policy daily_reports_delete
on public.daily_reports for delete to authenticated
using (
  public.daml_is_overall_admin()
  or (public.daml_is_branch_admin() and lower(trim(branch)) = public.daml_current_branch())
);

-- ---------------------------------------------------------------------------
-- Monthly reports
-- ---------------------------------------------------------------------------
create table if not exists public.monthly_reports (
  id uuid primary key default gen_random_uuid(),
  branch text not null,
  report_month date not null,
  report_data jsonb not null default '{}'::jsonb,
  collected numeric not null default 0,
  total_collected numeric not null default 0,
  total_disbursed numeric not null default 0,
  total_expenses numeric not null default 0,
  submitted_by uuid references auth.users(id) on delete set null,
  submitted_email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch, report_month)
);

create index if not exists monthly_reports_branch_month_idx
  on public.monthly_reports (branch, report_month desc);

alter table public.monthly_reports enable row level security;

drop policy if exists monthly_reports_select on public.monthly_reports;
drop policy if exists monthly_reports_insert on public.monthly_reports;
drop policy if exists monthly_reports_update on public.monthly_reports;
drop policy if exists monthly_reports_delete on public.monthly_reports;

create policy monthly_reports_select
on public.monthly_reports for select to authenticated
using (
  public.daml_is_overall_admin()
  or (public.daml_is_branch_admin() and lower(trim(branch)) = public.daml_current_branch())
);

create policy monthly_reports_insert
on public.monthly_reports for insert to authenticated
with check (
  public.daml_is_overall_admin()
  or (public.daml_is_branch_admin() and lower(trim(branch)) = public.daml_current_branch())
);

create policy monthly_reports_update
on public.monthly_reports for update to authenticated
using (
  public.daml_is_overall_admin()
  or (public.daml_is_branch_admin() and lower(trim(branch)) = public.daml_current_branch())
)
with check (
  public.daml_is_overall_admin()
  or (public.daml_is_branch_admin() and lower(trim(branch)) = public.daml_current_branch())
);

create policy monthly_reports_delete
on public.monthly_reports for delete to authenticated
using (
  public.daml_is_overall_admin()
  or (public.daml_is_branch_admin() and lower(trim(branch)) = public.daml_current_branch())
);

-- ---------------------------------------------------------------------------
-- Branch comments
-- ---------------------------------------------------------------------------
create table if not exists public.branch_comments (
  id uuid primary key default gen_random_uuid(),
  branch text not null,
  comment_text text not null,
  author text,
  submitted_by uuid references auth.users(id) on delete set null,
  submitted_email text,
  created_at timestamptz not null default now()
);

create index if not exists branch_comments_branch_created_idx
  on public.branch_comments (branch, created_at desc);

alter table public.branch_comments enable row level security;

drop policy if exists branch_comments_select on public.branch_comments;
drop policy if exists branch_comments_insert on public.branch_comments;

create policy branch_comments_select
on public.branch_comments for select to authenticated
using (
  public.daml_is_overall_admin()
  or (public.daml_is_branch_admin() and lower(trim(branch)) = public.daml_current_branch())
);

create policy branch_comments_insert
on public.branch_comments for insert to authenticated
with check (
  public.daml_is_overall_admin()
  or (public.daml_is_branch_admin() and lower(trim(branch)) = public.daml_current_branch())
);

-- ---------------------------------------------------------------------------
-- Zanaco distributions
-- ---------------------------------------------------------------------------
create table if not exists public.zanaco_distributions (
  id uuid primary key default gen_random_uuid(),
  distribution_date date not null,
  from_branch text not null default '',
  target_branch text not null,
  channel text not null,
  amount numeric not null default 0 check (amount >= 0),
  metadata jsonb not null default '{}'::jsonb,
  submitted_by uuid references auth.users(id) on delete set null,
  submitted_email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (distribution_date, from_branch, target_branch, channel)
);

create index if not exists zanaco_target_date_idx
  on public.zanaco_distributions (target_branch, distribution_date desc);

alter table public.zanaco_distributions enable row level security;

drop policy if exists zanaco_select on public.zanaco_distributions;
drop policy if exists zanaco_insert on public.zanaco_distributions;
drop policy if exists zanaco_update on public.zanaco_distributions;

create policy zanaco_select
on public.zanaco_distributions for select to authenticated
using (
  public.daml_is_overall_admin()
  or (
    public.daml_is_branch_admin()
    and (
      lower(trim(target_branch)) = public.daml_current_branch()
      or lower(trim(from_branch)) = public.daml_current_branch()
    )
  )
);

create policy zanaco_insert
on public.zanaco_distributions for insert to authenticated
with check (
  public.daml_is_overall_admin()
  or (
    public.daml_is_branch_admin()
    and lower(trim(from_branch)) = public.daml_current_branch()
  )
);

create policy zanaco_update
on public.zanaco_distributions for update to authenticated
using (
  public.daml_is_overall_admin()
  or (public.daml_is_branch_admin() and lower(trim(from_branch)) = public.daml_current_branch())
)
with check (
  public.daml_is_overall_admin()
  or (public.daml_is_branch_admin() and lower(trim(from_branch)) = public.daml_current_branch())
);



grant select, insert, update, delete on public.daily_reports to authenticated;
grant select, insert, update, delete on public.monthly_reports to authenticated;
grant select, insert on public.branch_comments to authenticated;
grant select, insert, update on public.zanaco_distributions to authenticated;

-- Existing reserved admins may already exist in profiles. Normalize them.
update public.profiles
set role = 'ovadmin', branch = null, updated_at = now()
where lower(email) = 'directaccessmoney@gmail.com';

update public.profiles
set role = 'branch_admin',
    branch = split_part(lower(email), '@', 1),
    updated_at = now()
where lower(email) in (
  'monze@directaccess.com',
  'mazabuka@directaccess.com',
  'lusaka@directaccess.com',
  'solwezi@directaccess.com',
  'lumezi@directaccess.com',
  'nakonde@directaccess.com',
  'mbala@directaccess.com',
  'kitwe@directaccess.com'
);

notify pgrst, 'reload schema';

-- Verification
select
  to_regclass('public.daily_reports') as daily_reports,
  to_regclass('public.monthly_reports') as monthly_reports,
  to_regclass('public.branch_comments') as branch_comments,
  to_regclass('public.zanaco_distributions') as zanaco_distributions;
