-- STEP 1 of resetting test data. SAFE: this only reads. It changes nothing.
-- Run it first and check that these are the shop and the numbers you expect to wipe.
-- (Run the whole file; the SQL Editor shows the result of the last query.)

select
  (select name from public.businesses limit 1)                                   as shop,
  (select count(*) from public.sarees)                                          as sarees_total,
  (select count(*) from public.sarees where status = 'available')               as sarees_available,
  (select count(*) from public.sarees where status = 'sold')                    as sarees_sold,
  (select count(*) from public.sales where status = 'confirmed')                as sales_confirmed,
  (select count(*) from public.sales where status = 'void')                     as sales_void,
  (select count(*) from public.sales where status = 'draft')                    as sales_draft,
  (select count(*) from public.sale_items)                                      as sale_items,
  (select count(*) from public.audit_events)                                    as audit_events,
  (select count(*) from public.business_members)                                as members_kept,
  (select count(*) from storage.objects where bucket_id = 'saree-photos')       as photo_files_not_touched,
  (select last_value from public.sku_counters limit 1)                          as last_sku_number,
  (select string_agg(year || ':' || last_value, ', ') from public.sale_counters) as sale_counters;
