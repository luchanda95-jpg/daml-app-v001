-- Optional helper. Run this only if dashboard loads but shows Supabase permission/RLS errors.
-- This keeps user-specific data protected while allowing authenticated users to read legacy loans
-- for matching/searching inside the client dashboard.

alter table if exists public.profiles enable row level security;
alter table if exists public.legacy_loans enable row level security;

create policy if not exists "profiles_select_own"
on public.profiles for select
to authenticated
using (auth.uid() = id);

create policy if not exists "profiles_insert_own"
on public.profiles for insert
to authenticated
with check (auth.uid() = id);

create policy if not exists "profiles_update_own"
on public.profiles for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

-- For legacy loans, use this only if your search RPC/table reads are blocked.
-- A stricter production policy can match borrower_email/borrower_mobile to the user's profile.
create policy if not exists "legacy_loans_authenticated_read"
on public.legacy_loans for select
to authenticated
using (true);
