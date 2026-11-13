-- OPTIONAL one-time cleanup. Before 002, editing a draft created a VOID row ("Replaced by edited draft").
-- Those rows were never confirmed sales and never touched stock. Run step 1 and LOOK at the rows first.

-- 1. Preview (safe, read only):
select s.id, s.customer_name, s.created_at, s.void_reason, s.total_collected_paise,
       (select count(*) from public.sale_items i where i.sale_id = s.id) as items
  from public.sales s
 where s.status = 'void' and s.void_reason = 'Replaced by edited draft' and s.confirmed_at is null
 order by s.created_at;

-- 2. If the list above is only junk you want gone, run this block. It deletes ONLY those rows.
-- begin;
--   delete from public.sale_items where sale_id in (
--     select id from public.sales
--      where status = 'void' and void_reason = 'Replaced by edited draft' and confirmed_at is null);
--   delete from public.sales
--    where status = 'void' and void_reason = 'Replaced by edited draft' and confirmed_at is null;
-- commit;
