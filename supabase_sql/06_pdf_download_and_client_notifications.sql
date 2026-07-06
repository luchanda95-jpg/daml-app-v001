-- DAML fix: PDF download support + client status notifications
-- Run this in Supabase SQL Editor after applying the Flutter patch.

-- Ensure application/notification columns used by the Flutter app exist.
alter table public.notifications
add column if not exists application_id uuid references public.applications(id) on delete cascade,
add column if not exists target_email text,
add column if not exists target_role text default 'client',
add column if not exists data jsonb default '{}'::jsonb;

alter table public.applications
add column if not exists submitted_by_user_id uuid references auth.users(id) on delete set null,
add column if not exists submitted_by_email text,
add column if not exists form_data jsonb default '{}'::jsonb;

-- Useful indexes for fast notification polling.
create index if not exists notifications_target_email_created_at_idx
on public.notifications (target_email, created_at desc);

create index if not exists applications_created_at_idx
on public.applications (created_at desc);

-- Keep RLS enabled.
alter table public.notifications enable row level security;
alter table public.applications enable row level security;

-- Replace notification policies safely.
drop policy if exists "authenticated insert notifications" on public.notifications;
drop policy if exists "authenticated read own notifications" on public.notifications;
drop policy if exists "authenticated update own notifications" on public.notifications;
drop policy if exists "authenticated read notifications" on public.notifications;
drop policy if exists "authenticated update notifications" on public.notifications;

create policy "authenticated insert notifications"
on public.notifications
for insert
to authenticated
with check (true);

create policy "authenticated read own notifications"
on public.notifications
for select
to authenticated
using (
  lower(coalesce(target_email, '')) = lower(coalesce(auth.jwt() ->> 'email', ''))
  or target_role = 'admin'
);

create policy "authenticated update own notifications"
on public.notifications
for update
to authenticated
using (
  lower(coalesce(target_email, '')) = lower(coalesce(auth.jwt() ->> 'email', ''))
  or target_role = 'admin'
)
with check (
  lower(coalesce(target_email, '')) = lower(coalesce(auth.jwt() ->> 'email', ''))
  or target_role = 'admin'
);

-- Storage policies: allow authenticated admin/user to download PDFs from private bucket.
drop policy if exists "application pdf read authenticated" on storage.objects;
create policy "application pdf read authenticated"
on storage.objects
for select
to authenticated
using (bucket_id = 'application-pdfs');

notify pgrst, 'reload schema';
