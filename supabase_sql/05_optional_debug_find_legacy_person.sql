-- Optional manual test in Supabase SQL Editor.
-- Replace the values below with the exact name/phone/email used during signup.
-- This does not use auth.uid(); it just confirms that the imported CSV has matching records.

select
  id,
  full_name,
  borrower_mobile,
  borrower_email,
  loan_status,
  principal_amount,
  balance_amount,
  next_due_date
from public.legacy_loans
where
  lower(coalesce(borrower_email, '')) = lower('PUT_EMAIL_HERE')
  or public.daml_normalize_phone(borrower_mobile) = public.daml_normalize_phone('PUT_PHONE_HERE')
  or public.daml_normalize_name(full_name) = public.daml_normalize_name('PUT_FULL_NAME_HERE')
limit 20;
