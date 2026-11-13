-- Manual, one-time bootstrap. Run in the Supabase SQL Editor AFTER 001_initial.sql.
-- There is deliberately no public/self-service way to join the shop.

-- 1. Sign in to the app once with the owner's Google (or email OTP) account, then find the UUID:
--    select id, email, created_at from auth.users order by created_at;

-- 2. Create the business and make the first user the owner (replace the email):
with b as (
  insert into public.businesses (name) values ('Aadav Sarees') returning id
)
insert into public.business_members (business_id, user_id, role)
select b.id, u.id, 'owner'
from b, auth.users u
where u.email = 'OWNER_EMAIL_HERE';

-- 3. After the spouse has signed in once, add them (replace the email):
insert into public.business_members (business_id, user_id, role)
select (select id from public.businesses limit 1), u.id, 'editor'
from auth.users u
where u.email = 'SPOUSE_EMAIL_HERE';

-- 4. Verify:
select m.role, u.email from public.business_members m join auth.users u on u.id = m.user_id;
