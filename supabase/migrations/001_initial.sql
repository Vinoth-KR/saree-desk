-- Aadav Saree Desk: initial schema, RLS, RPCs, storage policies.
-- Run once in the Supabase SQL Editor (or `supabase db push`).
-- Money is always integer paise. No cost/profit/GST fields exist by design.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- tables
create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table public.business_members (
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'editor')),
  created_at timestamptz not null default now(),
  primary key (business_id, user_id)
);
create index business_members_user_idx on public.business_members(user_id);

create table public.sku_counters (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  last_value bigint not null default 0
);

create table public.sale_counters (
  business_id uuid not null references public.businesses(id) on delete cascade,
  year int not null,
  last_value bigint not null default 0,
  primary key (business_id, year)
);

create table public.sarees (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  sku text not null,
  wholesale_receipt_date date not null,
  wholesale_bill_index text not null check (length(btrim(wholesale_bill_index)) > 0),
  description text not null check (length(btrim(description)) > 0),
  image_path text,
  marked_price_paise integer not null check (marked_price_paise > 0),
  status text not null default 'available' check (status in ('available', 'sold')),
  indexed_at timestamptz not null default now(),
  indexed_by uuid not null references auth.users(id),
  sold_at timestamptz,
  constraint sarees_business_sku_key unique (business_id, sku)
);
create index sarees_business_status_idx on public.sarees(business_id, status);
create index sarees_receipt_date_idx on public.sarees(business_id, wholesale_receipt_date);
create index sarees_description_idx on public.sarees(business_id, lower(description));
create index sarees_price_idx on public.sarees(business_id, marked_price_paise);

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  sale_number text,
  customer_name text not null default 'Walk-in customer',
  status text not null check (status in ('draft', 'confirmed', 'void')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  confirmed_at timestamptz,
  total_marked_paise bigint not null default 0 check (total_marked_paise >= 0),
  subtotal_negotiated_paise bigint not null default 0 check (subtotal_negotiated_paise >= 0),
  discount_percent_bp integer not null default 0 check (discount_percent_bp between 0 and 10000),
  order_discount_paise bigint not null default 0 check (order_discount_paise >= 0),
  total_collected_paise bigint not null default 0 check (total_collected_paise >= 0),
  idempotency_key uuid,
  void_reason text,
  voided_at timestamptz,
  voided_by uuid references auth.users(id),
  constraint sales_business_number_key unique (business_id, sale_number),
  constraint sales_idempotency_key unique (business_id, idempotency_key)
);
create index sales_business_status_idx on public.sales(business_id, status, created_at desc);

create table public.sale_items (
  sale_id uuid not null references public.sales(id),
  saree_id uuid not null references public.sarees(id),
  sku_at_sale text not null,
  description_at_sale text not null,
  image_path_at_sale text,
  marked_price_at_sale_paise integer not null check (marked_price_at_sale_paise > 0),
  negotiated_price_paise integer not null check (negotiated_price_paise >= 0),
  allocated_order_discount_paise integer not null default 0 check (allocated_order_discount_paise >= 0),
  final_sold_price_paise integer not null check (final_sold_price_paise >= 0),
  primary key (sale_id, saree_id)
);
create index sale_items_saree_idx on public.sale_items(saree_id);

create table public.audit_events (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id),
  actor_user_id uuid not null,
  action text not null,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_events_business_idx on public.audit_events(business_id, created_at desc);

-- ---------------------------------------------------------------- helpers
-- security definer avoids recursive RLS on business_members.
create or replace function public.is_member(p_business uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.business_members
    where business_id = p_business and user_id = auth.uid()
  );
$$;

create or replace function public.is_owner(p_business uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.business_members
    where business_id = p_business and user_id = auth.uid() and role = 'owner'
  );
$$;

revoke all on function public.is_member(uuid) from public, anon;
revoke all on function public.is_owner(uuid) from public, anon;
grant execute on function public.is_member(uuid) to authenticated;
grant execute on function public.is_owner(uuid) to authenticated;

-- Returns the caller's business id or raises. Single-shop app: first membership.
create or replace function public.my_business_id()
returns uuid
language plpgsql stable security definer
set search_path = public
as $$
declare v uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select business_id into v from public.business_members
   where user_id = auth.uid() order by created_at limit 1;
  if v is null then
    raise exception 'not authorized for this shop' using errcode = '42501';
  end if;
  return v;
end;
$$;
revoke all on function public.my_business_id() from public, anon;
grant execute on function public.my_business_id() to authenticated;

create or replace function public.next_sku(p_business uuid)
returns text
language plpgsql security definer
set search_path = public
as $$
declare n bigint;
begin
  insert into public.sku_counters(business_id, last_value) values (p_business, 1)
  on conflict (business_id) do update set last_value = public.sku_counters.last_value + 1
  returning last_value into n;
  return 'SR-' || lpad(n::text, 4, '0');
end;
$$;
revoke all on function public.next_sku(uuid) from public, anon, authenticated;

create or replace function public.next_sale_number(p_business uuid)
returns text
language plpgsql security definer
set search_path = public
as $$
declare n bigint; y int := extract(year from now())::int;
begin
  insert into public.sale_counters(business_id, year, last_value) values (p_business, y, 1)
  on conflict (business_id, year) do update set last_value = public.sale_counters.last_value + 1
  returning last_value into n;
  return 'SD-' || y || '-' || lpad(n::text, 6, '0');
end;
$$;
revoke all on function public.next_sale_number(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- RLS
alter table public.businesses enable row level security;
alter table public.business_members enable row level security;
alter table public.sku_counters enable row level security;
alter table public.sale_counters enable row level security;
alter table public.sarees enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.audit_events enable row level security;

-- Members can read; ALL writes go through security-definer RPCs.
create policy businesses_read on public.businesses
  for select to authenticated using (public.is_member(id));

create policy members_read on public.business_members
  for select to authenticated using (user_id = auth.uid() or public.is_owner(business_id));

create policy sarees_read on public.sarees
  for select to authenticated using (public.is_member(business_id));

create policy sales_read on public.sales
  for select to authenticated using (public.is_member(business_id));

create policy sale_items_read on public.sale_items
  for select to authenticated using (
    exists (select 1 from public.sales s where s.id = sale_id and public.is_member(s.business_id))
  );

create policy audit_read on public.audit_events
  for select to authenticated using (public.is_member(business_id));

-- counters: no policies => no client access at all.

revoke all on all tables in schema public from anon;
revoke insert, update, delete on all tables in schema public from authenticated;
grant select on public.businesses, public.business_members, public.sarees,
  public.sales, public.sale_items, public.audit_events to authenticated;

-- ---------------------------------------------------------------- RPCs
create or replace function public.add_saree(
  p_receipt_date date,
  p_bill_index text,
  p_description text,
  p_marked_price_paise integer,
  p_sku text default null,
  p_id uuid default null
) returns public.sarees
language plpgsql security definer
set search_path = public
as $$
declare
  b uuid := public.my_business_id();
  v_sku text;
  r public.sarees;
begin
  if p_receipt_date is null then raise exception 'Receipt date is required'; end if;
  if p_bill_index is null or btrim(p_bill_index) = '' then raise exception 'Bill index is required'; end if;
  if p_description is null or btrim(p_description) = '' then raise exception 'Description is required'; end if;
  if p_marked_price_paise is null or p_marked_price_paise <= 0 then
    raise exception 'Marked price must be greater than zero';
  end if;

  if p_sku is not null and btrim(p_sku) <> '' then
    v_sku := upper(btrim(p_sku));
    if exists (select 1 from public.sarees where business_id = b and sku = v_sku) then
      raise exception 'SKU % already exists', v_sku using errcode = '23505';
    end if;
  else
    -- Loop skips any SKU that was previously entered manually.
    loop
      v_sku := public.next_sku(b);
      exit when not exists (select 1 from public.sarees where business_id = b and sku = v_sku);
    end loop;
  end if;

  insert into public.sarees(id, business_id, sku, wholesale_receipt_date, wholesale_bill_index,
                            description, marked_price_paise, indexed_by)
  values (coalesce(p_id, gen_random_uuid()), b, v_sku, p_receipt_date, btrim(p_bill_index),
          btrim(p_description), p_marked_price_paise, auth.uid())
  returning * into r;

  insert into public.audit_events(business_id, actor_user_id, action, entity_id, metadata)
  values (b, auth.uid(), 'saree_added', r.id, jsonb_build_object('sku', r.sku));
  return r;
end;
$$;

create or replace function public.edit_saree_details(
  p_id uuid,
  p_receipt_date date,
  p_bill_index text,
  p_description text,
  p_marked_price_paise integer
) returns public.sarees
language plpgsql security definer
set search_path = public
as $$
declare b uuid := public.my_business_id(); r public.sarees;
begin
  if p_bill_index is null or btrim(p_bill_index) = '' then raise exception 'Bill index is required'; end if;
  if p_description is null or btrim(p_description) = '' then raise exception 'Description is required'; end if;
  if p_marked_price_paise is null or p_marked_price_paise <= 0 then
    raise exception 'Marked price must be greater than zero';
  end if;
  update public.sarees
     set wholesale_receipt_date = p_receipt_date,
         wholesale_bill_index = btrim(p_bill_index),
         description = btrim(p_description),
         marked_price_paise = p_marked_price_paise
   where id = p_id and business_id = b
   returning * into r;
  if r.id is null then raise exception 'Saree not found'; end if;
  insert into public.audit_events(business_id, actor_user_id, action, entity_id, metadata)
  values (b, auth.uid(), 'saree_edited', r.id, jsonb_build_object('sku', r.sku));
  return r;
end;
$$;

-- Called only after the storage object exists.
create or replace function public.set_saree_image(p_id uuid, p_image_path text)
returns public.sarees
language plpgsql security definer
set search_path = public
as $$
declare b uuid := public.my_business_id(); r public.sarees;
begin
  if p_image_path is null or p_image_path not like (b::text || '/' || p_id::text || '/%') then
    raise exception 'Invalid image path';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'saree-photos' and name = p_image_path) then
    raise exception 'Photo has not been uploaded yet';
  end if;
  update public.sarees set image_path = p_image_path
   where id = p_id and business_id = b returning * into r;
  if r.id is null then raise exception 'Saree not found'; end if;
  return r;
end;
$$;

-- p_items: [{"saree_id": "...", "negotiated_price_paise": 219900}, ...]
-- p_discount_bp: collective discount in basis points of the negotiated subtotal (1000 = 10%).
-- p_confirm = false saves a draft without touching stock.
create or replace function public.confirm_sale(
  p_items jsonb,
  p_customer_name text,
  p_discount_bp integer,
  p_idempotency_key uuid,
  p_confirm boolean default true,
  p_draft_id uuid default null
) returns public.sales
language plpgsql security definer
set search_path = public
as $$
declare
  b uuid := public.my_business_id();
  v_sale public.sales;
  v_cust text := coalesce(nullif(btrim(p_customer_name), ''), 'Walk-in customer');
  v_ids uuid[];
  v_count int;
  v_conflicts text;
  v_marked bigint := 0;
  v_sub bigint := 0;
  v_disc bigint;
  v_total bigint;
  v_alloc bigint := 0;
  v_n int;
  i int := 0;
  rec record;
  v_this_alloc bigint;
  v_neg bigint;
begin
  if p_idempotency_key is null then raise exception 'Idempotency key required'; end if;
  if p_discount_bp is null or p_discount_bp < 0 or p_discount_bp > 10000 then
    raise exception 'Discount must be between 0%% and 100%%';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Add at least one saree';
  end if;

  -- Replay of an already-processed request returns the stored sale.
  select * into v_sale from public.sales
   where business_id = b and idempotency_key = p_idempotency_key;
  if found then return v_sale; end if;

  select array_agg((e->>'saree_id')::uuid order by (e->>'saree_id')::uuid), count(*)
    into v_ids, v_count
    from jsonb_array_elements(p_items) e;
  if v_count <> (select count(distinct x) from unnest(v_ids) x) then
    raise exception 'Duplicate saree in sale';
  end if;

  -- Deterministic lock order (by id) prevents deadlocks between concurrent checkouts.
  perform 1 from public.sarees
   where id = any(v_ids) and business_id = b
   order by id for update;

  if (select count(*) from public.sarees where id = any(v_ids) and business_id = b) <> v_count then
    raise exception 'One or more sarees do not belong to this shop';
  end if;

  if p_confirm then
    select string_agg(sku, ', ' order by sku) into v_conflicts
      from public.sarees where id = any(v_ids) and business_id = b and status <> 'available';
    if v_conflicts is not null then
      raise exception 'Already sold: %', v_conflicts using errcode = '40001';
    end if;
  end if;

  -- Validate prices and compute totals (all integer paise).
  for rec in
    select s.id, s.marked_price_paise, (e->>'negotiated_price_paise')::numeric as neg
      from jsonb_array_elements(p_items) e
      join public.sarees s on s.id = (e->>'saree_id')::uuid
  loop
    if rec.neg is null or rec.neg < 0 or rec.neg <> trunc(rec.neg) or rec.neg > 2000000000 then
      raise exception 'Invalid negotiated price';
    end if;
    v_marked := v_marked + rec.marked_price_paise;
    v_sub := v_sub + rec.neg::bigint;
  end loop;

  v_disc := (v_sub * p_discount_bp) / 10000;           -- floor, integer paise
  v_total := v_sub - v_disc;
  if v_total < 0 then raise exception 'Total cannot be negative'; end if;

  if p_draft_id is not null then
    update public.sales set status = 'void', void_reason = 'Replaced by edited draft',
           voided_at = now(), voided_by = auth.uid()
     where id = p_draft_id and business_id = b and status = 'draft';
  end if;

  insert into public.sales(business_id, customer_name, status, created_by, confirmed_at,
      total_marked_paise, subtotal_negotiated_paise, discount_percent_bp, order_discount_paise,
      total_collected_paise, idempotency_key, sale_number)
  values (b, v_cust, case when p_confirm then 'confirmed' else 'draft' end, auth.uid(),
      case when p_confirm then now() end, v_marked, v_sub, p_discount_bp, v_disc, v_total,
      p_idempotency_key, case when p_confirm then public.next_sale_number(b) end)
  returning * into v_sale;

  -- Proportional allocation in integer paise; last item takes the remainder.
  v_n := v_count;
  for rec in
    select s.id, s.sku, s.description, s.image_path, s.marked_price_paise,
           (e->>'negotiated_price_paise')::bigint as neg
      from jsonb_array_elements(p_items) e
      join public.sarees s on s.id = (e->>'saree_id')::uuid
     order by s.id
  loop
    i := i + 1;
    v_neg := rec.neg;
    if i = v_n then
      v_this_alloc := v_disc - v_alloc;
    elsif v_sub = 0 then
      v_this_alloc := 0;
    else
      v_this_alloc := (v_neg * v_disc) / v_sub;
    end if;
    v_alloc := v_alloc + v_this_alloc;
    if v_this_alloc > v_neg then
      raise exception 'Discount allocation exceeds line price';
    end if;
    insert into public.sale_items(sale_id, saree_id, sku_at_sale, description_at_sale,
        image_path_at_sale, marked_price_at_sale_paise, negotiated_price_paise,
        allocated_order_discount_paise, final_sold_price_paise)
    values (v_sale.id, rec.id, rec.sku, rec.description, rec.image_path,
        rec.marked_price_paise, v_neg, v_this_alloc, v_neg - v_this_alloc);
  end loop;

  if (select sum(final_sold_price_paise) from public.sale_items where sale_id = v_sale.id) <> v_total then
    raise exception 'Allocation mismatch';
  end if;

  if p_confirm then
    update public.sarees set status = 'sold', sold_at = now()
     where id = any(v_ids) and business_id = b;
  end if;

  insert into public.audit_events(business_id, actor_user_id, action, entity_id, metadata)
  values (b, auth.uid(), case when p_confirm then 'sale_confirmed' else 'draft_saved' end, v_sale.id,
          jsonb_build_object('sale_number', v_sale.sale_number, 'total_collected_paise', v_total,
                             'items', v_count));
  return v_sale;
end;
$$;

-- Turn a saved draft into a confirmed sale (re-validates stock under lock).
create or replace function public.confirm_draft(p_draft_id uuid, p_idempotency_key uuid)
returns public.sales
language plpgsql security definer
set search_path = public
as $$
declare
  b uuid := public.my_business_id();
  d public.sales;
  v_items jsonb;
begin
  select * into d from public.sales where id = p_draft_id and business_id = b and status = 'draft';
  if d.id is null then raise exception 'Draft not found'; end if;
  select jsonb_agg(jsonb_build_object('saree_id', saree_id,
                                      'negotiated_price_paise', negotiated_price_paise))
    into v_items from public.sale_items where sale_id = d.id;
  return public.confirm_sale(v_items, d.customer_name, d.discount_percent_bp,
                             p_idempotency_key, true, d.id);
end;
$$;

create or replace function public.void_sale(p_sale_id uuid, p_reason text)
returns public.sales
language plpgsql security definer
set search_path = public
as $$
declare
  b uuid := public.my_business_id();
  s public.sales;
begin
  if p_reason is null or btrim(p_reason) = '' then raise exception 'A reason is required'; end if;

  select * into s from public.sales where id = p_sale_id and business_id = b for update;
  if s.id is null then raise exception 'Sale not found'; end if;
  if s.status = 'void' then raise exception 'Sale is already void'; end if;

  perform 1 from public.sarees
   where id in (select saree_id from public.sale_items where sale_id = s.id)
   order by id for update;

  if s.status = 'confirmed' then
    update public.sarees set status = 'available', sold_at = null
     where id in (select saree_id from public.sale_items where sale_id = s.id)
       and business_id = b;
  end if;

  update public.sales set status = 'void', void_reason = btrim(p_reason),
         voided_at = now(), voided_by = auth.uid()
   where id = s.id returning * into s;

  insert into public.audit_events(business_id, actor_user_id, action, entity_id, metadata)
  values (b, auth.uid(), 'sale_voided', s.id,
          jsonb_build_object('sale_number', s.sale_number, 'reason', btrim(p_reason)));
  return s;
end;
$$;

revoke all on function public.add_saree(date, text, text, integer, text, uuid) from public, anon;
revoke all on function public.edit_saree_details(uuid, date, text, text, integer) from public, anon;
revoke all on function public.set_saree_image(uuid, text) from public, anon;
revoke all on function public.confirm_sale(jsonb, text, integer, uuid, boolean, uuid) from public, anon;
revoke all on function public.confirm_draft(uuid, uuid) from public, anon;
revoke all on function public.void_sale(uuid, text) from public, anon;
grant execute on function public.add_saree(date, text, text, integer, text, uuid) to authenticated;
grant execute on function public.edit_saree_details(uuid, date, text, text, integer) to authenticated;
grant execute on function public.set_saree_image(uuid, text) to authenticated;
grant execute on function public.confirm_sale(jsonb, text, integer, uuid, boolean, uuid) to authenticated;
grant execute on function public.confirm_draft(uuid, uuid) to authenticated;
grant execute on function public.void_sale(uuid, text) to authenticated;

-- ---------------------------------------------------------------- storage
insert into storage.buckets (id, name, public)
values ('saree-photos', 'saree-photos', false)
on conflict (id) do update set public = false;

-- Path convention: {business_id}/{saree_id}/{unique-file}.jpg
create policy saree_photos_read on storage.objects
  for select to authenticated
  using (bucket_id = 'saree-photos'
         and public.is_member(((storage.foldername(name))[1])::uuid));

create policy saree_photos_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'saree-photos'
              and public.is_member(((storage.foldername(name))[1])::uuid));

-- No update/delete policies: photos are immutable; orphans are reclaimed manually later.

-- ---------------------------------------------------------------- realtime
alter publication supabase_realtime add table public.sarees;
alter publication supabase_realtime add table public.sales;
