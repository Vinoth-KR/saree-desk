-- Manual SQL test script. Run in the Supabase SQL Editor AFTER 001_initial.sql.
-- It creates two throwaway auth users and a throwaway business, exercises the RPCs by
-- impersonating users via request.jwt.claims, and ROLLS BACK at the end (nothing persists).
-- Each block raises an exception on failure and a NOTICE 'PASS ...' on success.

begin;

-- fixtures -------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email)
values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't-owner@example.test'),
       ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't-editor@example.test'),
       ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't-stranger@example.test'),
       ('00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't-viewer@example.test');
insert into public.businesses (id, name) values ('00000000-0000-0000-0000-0000000000b1', 'TEST SHOP');
insert into public.business_members (business_id, user_id, role)
values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', 'owner'),
       ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a2', 'editor'),
       ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a4', 'viewer');

-- User switching uses plain set_config calls (no helper functions), so it also works after the
-- role has been switched to 'authenticated'.

-- 1. two sarees, same bill, different SKUs ---------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true), set_config('role', 'authenticated', true);
do $$
declare a public.sarees; b public.sarees;
begin
  a := public.add_saree(date '2026-10-01', 'B-77', 'Blue silk', 249900);
  b := public.add_saree(date '2026-10-01', 'B-77', 'Red silk', 150000);
  assert a.sku <> b.sku, 'SKUs must differ';
  assert a.sku = 'SR-0001' and b.sku = 'SR-0002', 'sequential SKUs expected, got ' || a.sku || ',' || b.sku;
  raise notice 'PASS 1 sequential unique SKUs';
end $$;

-- 2. validation + duplicate manual SKU -------------------------------------
do $$
declare ok boolean;
begin
  begin perform public.add_saree(date '2026-10-01', '', 'x', 100); ok := false; exception when others then ok := true; end;
  assert ok, 'empty bill index must fail';
  begin perform public.add_saree(date '2026-10-01', 'B', '  ', 100); ok := false; exception when others then ok := true; end;
  assert ok, 'empty description must fail';
  begin perform public.add_saree(date '2026-10-01', 'B', 'x', 0); ok := false; exception when others then ok := true; end;
  assert ok, 'zero price must fail';
  begin perform public.add_saree(date '2026-10-01', 'B', 'x', -5); ok := false; exception when others then ok := true; end;
  assert ok, 'negative price must fail';
  begin perform public.add_saree(date '2026-10-01', 'B', 'dup', 100, 'sr-0001'); ok := false; exception when unique_violation then ok := true; end;
  assert ok, 'duplicate manual SKU must fail';
  raise notice 'PASS 2 validation and duplicate SKU';
end $$;

-- 3. single sale 2499 -> 2199 -------------------------------------------------
do $$
declare s public.sales; sid uuid; st text;
begin
  select id into sid from public.sarees where sku = 'SR-0001';
  s := public.confirm_sale(jsonb_build_array(jsonb_build_object('saree_id', sid, 'negotiated_price_paise', 219900)),
                           null, 0, gen_random_uuid());
  assert s.total_collected_paise = 219900, 'collected';
  assert s.total_marked_paise - s.total_collected_paise = 30000, 'discount 300';
  assert s.customer_name = 'Walk-in customer', 'walk-in default';
  select status into st from public.sarees where id = sid;
  assert st = 'sold', 'saree sold';
  raise notice 'PASS 3 single-item sale';
end $$;

-- 4. already-sold conflict leaves no partial state ---------------------------
do $$
declare a uuid; b uuid; ok boolean; n_before int; n_after int;
begin
  select id into a from public.sarees where sku = 'SR-0001';  -- sold
  select id into b from public.sarees where sku = 'SR-0002';  -- available
  select count(*) into n_before from public.sales;
  begin
    perform public.confirm_sale(jsonb_build_array(
        jsonb_build_object('saree_id', a, 'negotiated_price_paise', 100),
        jsonb_build_object('saree_id', b, 'negotiated_price_paise', 100)), 'X', 0, gen_random_uuid());
    ok := false;
  exception when others then ok := sqlerrm like 'Already sold: SR-0001%'; end;
  assert ok, 'must fail naming SR-0001';
  select count(*) into n_after from public.sales;
  assert n_before = n_after, 'no partial sale row';
  assert (select status from public.sarees where id = b) = 'available', 'SR-0002 untouched';
  raise notice 'PASS 4 conflict is atomic';
end $$;

-- 5. idempotency replay returns same sale -----------------------------------
do $$
declare b uuid; k uuid := gen_random_uuid(); s1 public.sales; s2 public.sales;
begin
  select id into b from public.sarees where sku = 'SR-0002';
  s1 := public.confirm_sale(jsonb_build_array(jsonb_build_object('saree_id', b, 'negotiated_price_paise', 140000)), 'Asha', 1000, k);
  s2 := public.confirm_sale(jsonb_build_array(jsonb_build_object('saree_id', b, 'negotiated_price_paise', 140000)), 'Asha', 1000, k);
  assert s1.id = s2.id, 'replay must return the same sale';
  assert s1.order_discount_paise = 14000 and s1.total_collected_paise = 126000, '10% math';
  raise notice 'PASS 5 idempotent confirm + percent discount';
end $$;

-- 6. void, repeat void rejected, history kept --------------------------------
do $$
declare sid uuid; ok boolean;
begin
  select id into sid from public.sales where customer_name = 'Asha';
  perform public.void_sale(sid, 'wrong item');
  assert (select status from public.sales where id = sid) = 'void', 'voided';
  assert (select status from public.sarees where sku = 'SR-0002') = 'available', 'restored';
  begin perform public.void_sale(sid, 'again'); ok := false; exception when others then ok := true; end;
  assert ok, 'repeat void must fail';
  begin perform public.void_sale(sid, ' '); ok := false; exception when others then ok := true; end;
  assert ok, 'reason required';
  assert (select count(*) from public.audit_events where action in ('sale_confirmed', 'sale_voided')) >= 3, 'audit rows';
  raise notice 'PASS 6 void flow and audit';
end $$;

-- 7. multi-item sale with rounding: final prices sum to collected --------------
do $$
declare s public.sales; a uuid; b uuid; c uuid; sumfinal bigint;
begin
  a := (public.add_saree(date '2026-10-02', 'B-78', 'p', 10001)).id;
  b := (public.add_saree(date '2026-10-02', 'B-78', 'q', 10001)).id;
  c := (public.add_saree(date '2026-10-02', 'B-78', 'r', 10001)).id;
  s := public.confirm_sale(jsonb_build_array(
        jsonb_build_object('saree_id', a, 'negotiated_price_paise', 10001),
        jsonb_build_object('saree_id', b, 'negotiated_price_paise', 10001),
        jsonb_build_object('saree_id', c, 'negotiated_price_paise', 10001)), 'Bulk', 333, gen_random_uuid());
  select sum(final_sold_price_paise) into sumfinal from public.sale_items where sale_id = s.id;
  assert sumfinal = s.total_collected_paise, 'allocation sum mismatch';
  raise notice 'PASS 7 allocation sums to collected';
end $$;

-- 8. stranger sees nothing and cannot call RPCs ---------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}', true), set_config('role', 'authenticated', true);
do $$
declare ok boolean;
begin
  assert (select count(*) from public.sarees) = 0, 'stranger sees sarees';
  assert (select count(*) from public.sales) = 0, 'stranger sees sales';
  assert (select count(*) from public.sale_items) = 0, 'stranger sees items';
  assert (select count(*) from public.business_members) = 0, 'stranger sees members';
  begin perform public.add_saree(date '2026-10-01', 'B', 'hack', 100); ok := false; exception when others then ok := true; end;
  assert ok, 'stranger add_saree must fail';
  begin insert into public.sarees(business_id, sku, wholesale_receipt_date, wholesale_bill_index, description, marked_price_paise, indexed_by)
        values ('00000000-0000-0000-0000-0000000000b1', 'X', now(), 'b', 'd', 1, '00000000-0000-0000-0000-0000000000a3');
        ok := false; exception when others then ok := true; end;
  assert ok, 'direct insert must be denied';
  raise notice 'PASS 8 stranger is locked out';
end $$;

-- 9. second member sees the shop's data ------------------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true), set_config('role', 'authenticated', true);
do $$
begin
  assert (select count(*) from public.sarees) >= 5, 'editor sees stock';
  raise notice 'PASS 9 second member can read';
end $$;

-- 10. (needs 002) editing a draft updates it IN PLACE: no void rows, same id --------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true), set_config('role', 'authenticated', true);
do $$
declare a uuid; b uuid; d1 public.sales; d2 public.sales; c public.sales; voids_before int; n_items int;
begin
  a := (public.add_saree(date '2026-10-03', 'B-79', 'draft-a', 100000)).id;
  b := (public.add_saree(date '2026-10-03', 'B-79', 'draft-b', 200000)).id;
  select count(*) into voids_before from public.sales where status = 'void';

  d1 := public.confirm_sale(jsonb_build_array(jsonb_build_object('saree_id', a, 'negotiated_price_paise', 100000)),
                            'Draft Person', 0, gen_random_uuid(), false);
  assert d1.status = 'draft' and d1.sale_number is null, 'draft created';
  assert (select status from public.sarees where id = a) = 'available', 'draft must not change stock';

  d2 := public.confirm_sale(jsonb_build_array(
          jsonb_build_object('saree_id', a, 'negotiated_price_paise', 90000),
          jsonb_build_object('saree_id', b, 'negotiated_price_paise', 200000)),
        'Draft Person', 1000, gen_random_uuid(), false, d1.id);
  assert d2.id = d1.id, 'edit keeps the same sale row';
  select count(*) into n_items from public.sale_items where sale_id = d1.id;
  assert n_items = 2, 'items replaced';
  assert (select count(*) from public.sales where status = 'void') = voids_before, 'editing a draft must not create a void';

  c := public.confirm_draft(d1.id, gen_random_uuid());
  assert c.id = d1.id and c.status = 'confirmed' and c.sale_number is not null, 'same row becomes confirmed';
  assert c.total_collected_paise = 261000, 'collected = 290000 - 10%';
  assert (select count(*) from public.sales where status = 'void') = voids_before, 'confirming a draft must not create a void';
  assert (select count(*) from public.sarees where id in (a, b) and status = 'sold') = 2, 'both sold';
  raise notice 'PASS 10 draft edit/confirm in place, no void rows';
end $$;

-- 11. (needs 002) discard draft ----------------------------------------------------
do $$
declare a uuid; d public.sales; ok boolean;
begin
  a := (public.add_saree(date '2026-10-03', 'B-80', 'discard-me', 50000)).id;
  d := public.confirm_sale(jsonb_build_array(jsonb_build_object('saree_id', a, 'negotiated_price_paise', 50000)),
                           'Gone', 0, gen_random_uuid(), false);
  perform public.discard_draft(d.id);
  assert not exists (select 1 from public.sales where id = d.id), 'draft removed';
  assert not exists (select 1 from public.sale_items where sale_id = d.id), 'items removed';
  assert (select status from public.sarees where id = a) = 'available', 'stock untouched';
  assert exists (select 1 from public.audit_events where action = 'draft_discarded' and entity_id = d.id), 'audit kept';
  begin perform public.discard_draft(d.id); ok := false; exception when others then ok := true; end;
  assert ok, 'discarding twice must fail';
  -- a confirmed sale can never be discarded
  select * into d from public.sales where status = 'confirmed' limit 1;
  begin perform public.discard_draft(d.id); ok := false; exception when others then ok := true; end;
  assert ok, 'confirmed sale cannot be discarded';
  raise notice 'PASS 11 discard draft';
end $$;

-- 12. (needs 002) roles ---------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true), set_config('role', 'authenticated', true);  -- viewer
do $$
declare ok boolean;
begin
  assert (select count(*) from public.sarees) > 0, 'viewer can read';
  begin perform public.add_saree(date '2026-10-01', 'B', 'nope', 100); ok := false; exception when others then ok := sqlerrm like 'Read-only%'; end;
  assert ok, 'viewer cannot add';
  begin perform public.list_members(); ok := false; exception when others then ok := true; end;
  assert ok, 'viewer cannot list members';
  raise notice 'PASS 12a viewer is read-only';
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true), set_config('role', 'authenticated', true);  -- editor
do $$
declare ok boolean;
begin
  perform public.add_saree(date '2026-10-04', 'B-81', 'editor can add', 100);
  begin perform public.add_member('t-stranger@example.test', 'editor'); ok := false; exception when others then ok := true; end;
  assert ok, 'editor cannot add members';
  raise notice 'PASS 12b editor can write but not manage members';
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true), set_config('role', 'authenticated', true);  -- owner
do $$
declare ok boolean; n int;
begin
  select count(*) into n from public.list_members();
  assert n = 3, 'owner sees 3 members, got ' || n;
  perform public.add_member('t-stranger@example.test', 'viewer');
  assert (select role from public.business_members where user_id = '00000000-0000-0000-0000-0000000000a3') = 'viewer', 'added as viewer';
  perform public.set_member_role('00000000-0000-0000-0000-0000000000a3', 'editor');
  assert (select role from public.business_members where user_id = '00000000-0000-0000-0000-0000000000a3') = 'editor', 'role changed';
  perform public.remove_member('00000000-0000-0000-0000-0000000000a3');
  assert not exists (select 1 from public.business_members where user_id = '00000000-0000-0000-0000-0000000000a3'), 'removed';
  begin perform public.add_member('nobody@example.test', 'editor'); ok := false; exception when others then ok := true; end;
  assert ok, 'unknown email must fail';
  begin perform public.set_member_role('00000000-0000-0000-0000-0000000000a1', 'editor'); ok := false; exception when others then ok := sqlerrm like '%at least one owner%'; end;
  assert ok, 'last owner cannot be demoted';
  begin perform public.remove_member('00000000-0000-0000-0000-0000000000a1'); ok := false; exception when others then ok := true; end;
  assert ok, 'owner cannot remove self';
  raise notice 'PASS 12c owner manages members, last-owner protected';
end $$;

-- 13. (needs 003) delete stock ----------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true), set_config('role', 'authenticated', true);
do $$
declare a uuid; b uuid; sku_a text; ok boolean; d public.sales; n_before int; sold_id uuid; voided_id uuid;
begin
  -- a never-sold saree can be deleted, and leaves an audit event
  a := (public.add_saree(date '2026-10-05', 'B-90', 'delete me', 10000)).id;
  select sku into sku_a from public.sarees where id = a;
  perform public.delete_saree(a);
  assert not exists (select 1 from public.sarees where id = a), 'saree removed';
  assert exists (select 1 from public.audit_events where action = 'saree_deleted' and entity_id = a
                  and metadata->>'sku' = sku_a), 'audit event with the SKU';

  -- the SKU number is never handed out again
  b := (public.add_saree(date '2026-10-05', 'B-90', 'after delete', 10000)).id;
  assert (select sku from public.sarees where id = b) > sku_a, 'next SKU must be higher than the deleted ' || sku_a;

  -- a sold saree (sales history) cannot be deleted
  select id into sold_id from public.sarees where sku = 'SR-0001';
  begin perform public.delete_saree(sold_id); ok := false;
  exception when others then ok := sqlerrm like '%sales history%'; end;
  assert ok, 'sold saree must not be deletable (sales history)';
  assert exists (select 1 from public.sarees where id = sold_id), 'sold saree still there';

  -- a saree that only has a VOID sale also keeps its history
  select id into voided_id from public.sarees where sku = 'SR-0002';
  begin perform public.delete_saree(voided_id); ok := false;
  exception when others then ok := sqlerrm like '%sales history%'; end;
  assert ok, 'saree with a void sale must not be deletable';

  -- a saree in a DRAFT cannot be deleted until the draft is discarded
  a := (public.add_saree(date '2026-10-05', 'B-91', 'in a draft', 20000)).id;
  d := public.confirm_sale(jsonb_build_array(jsonb_build_object('saree_id', a, 'negotiated_price_paise', 20000)),
                           'Draft Buyer', 0, gen_random_uuid(), false);
  begin perform public.delete_saree(a); ok := false;
  exception when others then ok := sqlerrm like '%draft%'; end;
  assert ok, 'saree in a draft must not be deletable';
  perform public.discard_draft(d.id);
  perform public.delete_saree(a);
  assert not exists (select 1 from public.sarees where id = a), 'deletable once the draft is discarded';

  -- unknown id
  begin perform public.delete_saree(gen_random_uuid()); ok := false;
  exception when others then ok := sqlerrm like '%not found%'; end;
  assert ok, 'unknown id must fail cleanly';
  raise notice 'PASS 13a delete rules (never sold only, SKU not reused, audit kept)';
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true), set_config('role', 'authenticated', true);
do $$
declare t uuid; ok boolean;
begin
  select id into t from public.sarees where status = 'available' limit 1;
  begin perform public.delete_saree(t); ok := false; exception when others then ok := sqlerrm like 'Read-only%'; end;
  assert ok, 'viewer cannot delete';
  assert exists (select 1 from public.sarees where id = t), 'still there after viewer attempt';
  raise notice 'PASS 13b viewer cannot delete';
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}', true), set_config('role', 'authenticated', true);
do $$
declare ok boolean;
begin
  begin perform public.delete_saree(gen_random_uuid()); ok := false; exception when others then ok := true; end;
  assert ok, 'stranger cannot call delete_saree';
  raise notice 'PASS 13c stranger cannot delete';
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true), set_config('role', 'authenticated', true);
do $$
declare a uuid;
begin
  a := (public.add_saree(date '2026-10-06', 'B-92', 'editor entry', 5000)).id;
  perform public.delete_saree(a);
  assert not exists (select 1 from public.sarees where id = a), 'editor can delete';
  raise notice 'PASS 13d editor can delete never-sold stock';
end $$;

select set_config('role', 'postgres', true);
rollback;  -- nothing from this script persists

-- Race test (manual, needs two SQL Editor tabs):
--   Tab A: begin; select * from public.sarees where sku='SR-0001' for update;  -- hold the lock
--   Tab B: select public.confirm_sale(...same saree...)  -- blocks until A ends
--   Tab A: rollback;  Tab B then proceeds. Exactly one of two overlapping confirms ever succeeds,
--   because the loser sees status <> 'available' after acquiring the row lock.
