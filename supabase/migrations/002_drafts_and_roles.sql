-- 002: drafts are edited/confirmed IN PLACE (no void rows), drafts can be discarded,
-- and members get real roles (owner / editor / viewer) with a member-management API.
-- Run once in the Supabase SQL Editor AFTER 001_initial.sql.

-- ------------------------------------------------------------------ roles
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
     where conrelid = 'public.business_members'::regclass
       and contype = 'c' and pg_get_constraintdef(oid) like '%role%'
  loop
    execute format('alter table public.business_members drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.business_members
  add constraint business_members_role_check check (role in ('owner', 'editor', 'viewer'));

create or replace function public.can_write(p_business uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.business_members
    where business_id = p_business and user_id = auth.uid() and role in ('owner', 'editor')
  );
$$;
revoke all on function public.can_write(uuid) from public, anon;
grant execute on function public.can_write(uuid) to authenticated;

-- Every RPC that calls my_business_id() mutates data, so viewers are rejected here.
create or replace function public.my_business_id()
returns uuid
language plpgsql stable security definer
set search_path = public
as $$
declare v uuid; r text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select business_id, role into v, r from public.business_members
   where user_id = auth.uid() order by created_at limit 1;
  if v is null then
    raise exception 'not authorized for this shop' using errcode = '42501';
  end if;
  if r = 'viewer' then
    raise exception 'Read-only access: ask the owner for editor access' using errcode = '42501';
  end if;
  return v;
end;
$$;

-- Only owners/editors may upload photos.
drop policy if exists saree_photos_insert on storage.objects;
create policy saree_photos_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'saree-photos'
              and public.can_write(((storage.foldername(name))[1])::uuid));

-- ------------------------------------------------------------------ drafts
-- p_draft_id set: the existing draft row is UPDATED (items replaced). If p_confirm is true the
-- same row becomes the confirmed sale. No void row is ever created for a draft.
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
  v_draft public.sales;
  v_cust text := coalesce(nullif(btrim(p_customer_name), ''), 'Walk-in customer');
  v_ids uuid[];
  v_count int;
  v_conflicts text;
  v_marked bigint := 0;
  v_sub bigint := 0;
  v_disc bigint;
  v_total bigint;
  v_alloc bigint := 0;
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

  if p_draft_id is not null then
    select * into v_draft from public.sales
     where id = p_draft_id and business_id = b and status = 'draft' for update;
    if v_draft.id is null then
      raise exception 'Draft not found (it may already be confirmed or discarded)';
    end if;
  end if;

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

  v_disc := (v_sub * p_discount_bp) / 10000;
  v_total := v_sub - v_disc;
  if v_total < 0 then raise exception 'Total cannot be negative'; end if;

  if v_draft.id is not null then
    delete from public.sale_items where sale_id = v_draft.id;
    update public.sales
       set customer_name = v_cust,
           status = case when p_confirm then 'confirmed' else 'draft' end,
           confirmed_at = case when p_confirm then now() end,
           total_marked_paise = v_marked,
           subtotal_negotiated_paise = v_sub,
           discount_percent_bp = p_discount_bp,
           order_discount_paise = v_disc,
           total_collected_paise = v_total,
           idempotency_key = p_idempotency_key,
           sale_number = case when p_confirm then public.next_sale_number(b) else sale_number end
     where id = v_draft.id
     returning * into v_sale;
  else
    insert into public.sales(business_id, customer_name, status, created_by, confirmed_at,
        total_marked_paise, subtotal_negotiated_paise, discount_percent_bp, order_discount_paise,
        total_collected_paise, idempotency_key, sale_number)
    values (b, v_cust, case when p_confirm then 'confirmed' else 'draft' end, auth.uid(),
        case when p_confirm then now() end, v_marked, v_sub, p_discount_bp, v_disc, v_total,
        p_idempotency_key, case when p_confirm then public.next_sale_number(b) end)
    returning * into v_sale;
  end if;

  -- Proportional allocation in integer paise; last item takes the remainder.
  for rec in
    select s.id, s.sku, s.description, s.image_path, s.marked_price_paise,
           (e->>'negotiated_price_paise')::bigint as neg
      from jsonb_array_elements(p_items) e
      join public.sarees s on s.id = (e->>'saree_id')::uuid
     order by s.id
  loop
    i := i + 1;
    v_neg := rec.neg;
    if i = v_count then
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
  values (b, auth.uid(),
          case when p_confirm then 'sale_confirmed'
               when v_draft.id is not null then 'draft_updated'
               else 'draft_saved' end,
          v_sale.id,
          jsonb_build_object('sale_number', v_sale.sale_number, 'total_collected_paise', v_total,
                             'items', v_count, 'from_draft', v_draft.id is not null));
  return v_sale;
end;
$$;

-- Discarding removes an unconfirmed draft. Drafts never touched stock. The audit event keeps a record.
create or replace function public.discard_draft(p_sale_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  b uuid := public.my_business_id();
  s public.sales;
  v_skus text;
begin
  select * into s from public.sales
   where id = p_sale_id and business_id = b and status = 'draft' for update;
  if s.id is null then
    raise exception 'Draft not found (only unconfirmed drafts can be discarded)';
  end if;
  select string_agg(sku_at_sale, ', ' order by sku_at_sale) into v_skus
    from public.sale_items where sale_id = s.id;
  delete from public.sale_items where sale_id = s.id;
  delete from public.sales where id = s.id;
  insert into public.audit_events(business_id, actor_user_id, action, entity_id, metadata)
  values (b, auth.uid(), 'draft_discarded', s.id,
          jsonb_build_object('customer', s.customer_name, 'skus', v_skus,
                             'total_collected_paise', s.total_collected_paise));
end;
$$;

revoke all on function public.discard_draft(uuid) from public, anon;
grant execute on function public.discard_draft(uuid) to authenticated;

-- ------------------------------------------------------------------ team management
-- Owner only. Emails come from auth.users, which clients cannot read directly.
create or replace function public.list_members()
returns table (user_id uuid, email text, role text, created_at timestamptz)
language plpgsql security definer
set search_path = ''
as $$
declare b uuid; r text;
begin
  select m.business_id, m.role into b, r from public.business_members m
   where m.user_id = auth.uid() order by m.created_at limit 1;
  if b is null or r <> 'owner' then
    raise exception 'Only the owner can manage members' using errcode = '42501';
  end if;
  return query
    select m.user_id, u.email::text, m.role, m.created_at
      from public.business_members m
      join auth.users u on u.id = m.user_id
     where m.business_id = b
     order by m.created_at;
end;
$$;

create or replace function public.add_member(p_email text, p_role text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare b uuid; r text; v_user uuid;
begin
  select m.business_id, m.role into b, r from public.business_members m
   where m.user_id = auth.uid() order by m.created_at limit 1;
  if b is null or r <> 'owner' then
    raise exception 'Only the owner can manage members' using errcode = '42501';
  end if;
  if p_role not in ('owner', 'editor', 'viewer') then raise exception 'Invalid role'; end if;
  select u.id into v_user from auth.users u where lower(u.email) = lower(btrim(p_email)) limit 1;
  if v_user is null then
    raise exception 'No account with that email yet. Ask them to sign in once with Google, or create the user in Supabase first.';
  end if;
  insert into public.business_members(business_id, user_id, role)
  values (b, v_user, p_role)
  on conflict (business_id, user_id) do update set role = excluded.role;
  insert into public.audit_events(business_id, actor_user_id, action, entity_id, metadata)
  values (b, auth.uid(), 'member_added', v_user, jsonb_build_object('role', p_role));
end;
$$;

create or replace function public.set_member_role(p_user uuid, p_role text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare b uuid; r text; v_old text;
begin
  select m.business_id, m.role into b, r from public.business_members m
   where m.user_id = auth.uid() order by m.created_at limit 1;
  if b is null or r <> 'owner' then
    raise exception 'Only the owner can manage members' using errcode = '42501';
  end if;
  if p_role not in ('owner', 'editor', 'viewer') then raise exception 'Invalid role'; end if;
  select m.role into v_old from public.business_members m
   where m.business_id = b and m.user_id = p_user for update;
  if v_old is null then raise exception 'Member not found'; end if;
  if v_old = 'owner' and p_role <> 'owner'
     and (select count(*) from public.business_members m where m.business_id = b and m.role = 'owner') <= 1 then
    raise exception 'The shop needs at least one owner';
  end if;
  update public.business_members set role = p_role where business_id = b and user_id = p_user;
  insert into public.audit_events(business_id, actor_user_id, action, entity_id, metadata)
  values (b, auth.uid(), 'member_role_changed', p_user, jsonb_build_object('from', v_old, 'to', p_role));
end;
$$;

create or replace function public.remove_member(p_user uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare b uuid; r text; v_old text;
begin
  select m.business_id, m.role into b, r from public.business_members m
   where m.user_id = auth.uid() order by m.created_at limit 1;
  if b is null or r <> 'owner' then
    raise exception 'Only the owner can manage members' using errcode = '42501';
  end if;
  if p_user = auth.uid() then raise exception 'You cannot remove yourself'; end if;
  select m.role into v_old from public.business_members m
   where m.business_id = b and m.user_id = p_user for update;
  if v_old is null then raise exception 'Member not found'; end if;
  if v_old = 'owner'
     and (select count(*) from public.business_members m where m.business_id = b and m.role = 'owner') <= 1 then
    raise exception 'The shop needs at least one owner';
  end if;
  delete from public.business_members where business_id = b and user_id = p_user;
  insert into public.audit_events(business_id, actor_user_id, action, entity_id, metadata)
  values (b, auth.uid(), 'member_removed', p_user, jsonb_build_object('role', v_old));
end;
$$;

revoke all on function public.list_members() from public, anon;
revoke all on function public.add_member(text, text) from public, anon;
revoke all on function public.set_member_role(uuid, text) from public, anon;
revoke all on function public.remove_member(uuid) from public, anon;
grant execute on function public.list_members() to authenticated;
grant execute on function public.add_member(text, text) to authenticated;
grant execute on function public.set_member_role(uuid, text) to authenticated;
grant execute on function public.remove_member(uuid) to authenticated;
