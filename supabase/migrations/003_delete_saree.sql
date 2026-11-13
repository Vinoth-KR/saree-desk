-- 003: delete a stock entry (owner or editor).
-- Run once in the Supabase SQL Editor AFTER 001 and 002.
--
-- Rules:
--  * A saree that appears in ANY sale (confirmed, void or draft) cannot be deleted. Sales history is
--    never destroyed, and the sale_items foreign key would refuse it anyway.
--  * Only stock that has never been in a sale can be deleted (typos, duplicates, test entries).
--  * The saree row is locked first, so a concurrent checkout either sees it gone or makes it undeletable.
--  * The SKU counter is never rolled back, so a deleted SKU number is not handed out again.
--  * The photo file in Storage is NOT removed (storage objects are immutable in this app). The audit event
--    records the image path so orphaned files can be cleaned up from the Storage dashboard.

create or replace function public.delete_saree(p_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  b uuid := public.my_business_id();  -- also rejects viewers
  s public.sarees;
  v_sale record;
begin
  select * into s from public.sarees where id = p_id and business_id = b for update;
  if s.id is null then
    raise exception 'Saree not found (it may already have been deleted)';
  end if;

  -- Prefer reporting a real sale over a draft, so the message points at the history that blocks deletion.
  select sa.sale_number, sa.status, sa.customer_name into v_sale
    from public.sale_items si
    join public.sales sa on sa.id = si.sale_id
   where si.saree_id = s.id
   order by (sa.status = 'draft') asc, sa.created_at desc
   limit 1;

  if found then
    if v_sale.status = 'draft' then
      raise exception '% is in a draft sale for %. Discard or edit that draft first, then delete the saree.',
        s.sku, v_sale.customer_name;
    end if;
    raise exception '% is part of sales history (%). Sales history is kept, so this saree cannot be deleted.',
      s.sku, coalesce(v_sale.sale_number, 'sale');
  end if;

  if s.status <> 'available' then
    raise exception '% is not available, so it cannot be deleted.', s.sku;
  end if;

  delete from public.sarees where id = s.id;

  insert into public.audit_events(business_id, actor_user_id, action, entity_id, metadata)
  values (b, auth.uid(), 'saree_deleted', s.id,
          jsonb_build_object('sku', s.sku, 'description', s.description,
                             'marked_price_paise', s.marked_price_paise,
                             'wholesale_bill_index', s.wholesale_bill_index,
                             'wholesale_receipt_date', s.wholesale_receipt_date,
                             'image_path', s.image_path));
end;
$$;

revoke all on function public.delete_saree(uuid) from public, anon;
grant execute on function public.delete_saree(uuid) to authenticated;
