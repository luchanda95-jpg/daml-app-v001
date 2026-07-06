-- DAML Supabase admin visibility fix
-- Run this in Supabase SQL Editor after applying the Flutter patch.
-- It lets authenticated overall admins view applications, notifications, and PDF files.

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
alter table public.applications enable row level security;
alter table public.notifications enable row level security;

alter table public.applications
  add column if not exists submitted_by_user_id uuid references auth.users(id) on delete set null,
  add column if not exists submitted_by_email text,
  add column if not exists form_data jsonb default '{}'::jsonb;

alter table public.notifications
  add column if not exists created_by_user_id uuid references auth.users(id) on delete set null,
  add column if not exists target_role text default 'admin',
  add column if not exists target_email text,
  add column if not exists data jsonb default '{}'::jsonb;

create or replace function public.is_overall_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from auth.users u
    left join public.profiles p on p.id = u.id
    where u.id = auth.uid()
      and (
        lower(coalesce(u.email, p.email, '')) = 'directaccessmoney@gmail.com'
        or lower(coalesce(p.role, u.raw_user_meta_data->>'role', '')) in ('ovadmin', 'overall_admin', 'admin')
      )
  );
$$;

grant execute on function public.is_overall_admin() to authenticated;

-- Profiles policies
DROP POLICY IF EXISTS profiles_select_own_or_admin ON public.profiles;
DROP POLICY IF EXISTS profiles_insert_own ON public.profiles;
DROP POLICY IF EXISTS profiles_update_own ON public.profiles;

CREATE POLICY profiles_select_own_or_admin
ON public.profiles FOR SELECT
TO authenticated
USING (auth.uid() = id OR public.is_overall_admin());

CREATE POLICY profiles_insert_own
ON public.profiles FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

CREATE POLICY profiles_update_own
ON public.profiles FOR UPDATE
TO authenticated
USING (auth.uid() = id OR public.is_overall_admin())
WITH CHECK (auth.uid() = id OR public.is_overall_admin());

-- Applications policies
DROP POLICY IF EXISTS clients_insert_own_applications ON public.applications;
DROP POLICY IF EXISTS clients_view_own_applications ON public.applications;
DROP POLICY IF EXISTS admins_view_all_applications ON public.applications;
DROP POLICY IF EXISTS admins_update_all_applications ON public.applications;
DROP POLICY IF EXISTS "clients insert own applications" ON public.applications;
DROP POLICY IF EXISTS "clients view own applications" ON public.applications;
DROP POLICY IF EXISTS "authenticated view applications" ON public.applications;
DROP POLICY IF EXISTS "authenticated update applications" ON public.applications;

CREATE POLICY clients_insert_own_applications
ON public.applications FOR INSERT
TO authenticated
WITH CHECK (submitted_by_user_id = auth.uid());

CREATE POLICY clients_view_own_applications
ON public.applications FOR SELECT
TO authenticated
USING (submitted_by_user_id = auth.uid());

CREATE POLICY admins_view_all_applications
ON public.applications FOR SELECT
TO authenticated
USING (public.is_overall_admin());

CREATE POLICY admins_update_all_applications
ON public.applications FOR UPDATE
TO authenticated
USING (public.is_overall_admin())
WITH CHECK (public.is_overall_admin());

-- Notifications policies
DROP POLICY IF EXISTS clients_insert_admin_notifications ON public.notifications;
DROP POLICY IF EXISTS admins_read_notifications ON public.notifications;
DROP POLICY IF EXISTS admins_update_notifications ON public.notifications;
DROP POLICY IF EXISTS "authenticated insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "authenticated read notifications" ON public.notifications;
DROP POLICY IF EXISTS "authenticated update notifications" ON public.notifications;

CREATE POLICY clients_insert_admin_notifications
ON public.notifications FOR INSERT
TO authenticated
WITH CHECK (created_by_user_id = auth.uid() OR created_by_user_id IS NULL);

CREATE POLICY admins_read_notifications
ON public.notifications FOR SELECT
TO authenticated
USING (public.is_overall_admin() OR created_by_user_id = auth.uid());

CREATE POLICY admins_update_notifications
ON public.notifications FOR UPDATE
TO authenticated
USING (public.is_overall_admin() OR created_by_user_id = auth.uid())
WITH CHECK (public.is_overall_admin() OR created_by_user_id = auth.uid());

-- Storage policies for application PDFs
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('application-pdfs', 'application-pdfs', false, 10485760, array['application/pdf'])
on conflict (id) do update
set public = false,
    file_size_limit = 10485760,
    allowed_mime_types = array['application/pdf'];

DROP POLICY IF EXISTS application_pdf_upload_authenticated ON storage.objects;
DROP POLICY IF EXISTS application_pdf_read_owner_or_admin ON storage.objects;
DROP POLICY IF EXISTS "application pdf upload authenticated" ON storage.objects;
DROP POLICY IF EXISTS "application pdf read authenticated" ON storage.objects;

CREATE POLICY application_pdf_upload_authenticated
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'application-pdfs');

CREATE POLICY application_pdf_read_owner_or_admin
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'application-pdfs'
  AND (
    public.is_overall_admin()
    OR owner = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.applications a
      WHERE a.pdf_path = storage.objects.name
        AND a.submitted_by_user_id = auth.uid()
    )
  )
);

notify pgrst, 'reload schema';

-- Verify latest applications/notifications exist
select id, client_name, submitted_by_email, status, pdf_path, created_at
from public.applications
order by created_at desc
limit 5;

select id, title, message, type, is_read, target_role, target_email, created_at
from public.notifications
order by created_at desc
limit 5;
