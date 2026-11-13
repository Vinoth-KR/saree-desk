-- STEP 2 of resetting test data. DESTRUCTIVE AND NOT REVERSIBLE.
-- Run 1_preview_counts.sql first. Supabase free-tier projects have no automatic backup, so export
-- anything you want to keep (Tools > Export in the app) BEFORE running this.
--
-- What it does, in one transaction (all or nothing):
--   mode 'everything'        deletes ALL sale items, ALL sales (confirmed, void and drafts) and ALL stock.
--   mode 'drafts_and_voids'  deletes only draft and void sales. Stock and confirmed sales stay.
-- What it never touches: the shop, members and roles, and the photo files in Storage.
--
-- HOW TO RUN: edit the three settings below, then run the whole file.

do $$
declare
  -- 1. SAFETY LOCK. The script refuses to run until this is exactly: DELETE TEST DATA
  confirm_phrase text    := 'change me';

  -- 2. 'everything' or 'drafts_and_voids'
  mode           text    := 'everything';

  -- 3. Only for mode 'everything'. true = the next saree is SR-0001 and the next sale is
  --    SD-<year>-000001 again. Only do this BEFORE you have printed any real labels, because
  --    SKU numbers will be handed out again. false = numbering carries on from where it was.
  reset_numbering boolean := true;

  n_items bigint; n_sales bigint; n_sarees bigint; n_audit bigint := 0;
begin
  if confirm_phrase is distinct from 'DELETE TEST DATA' then
    raise exception 'NOT RUN. Set confirm_phrase to exactly: DELETE TEST DATA';
  end if;

  if mode = 'everything' then
    delete from public.sale_items where true;
    get diagnostics n_items = row_count;
    delete from public.sales where true;
    get diagnostics n_sales = row_count;
    delete from public.sarees where true;
    get diagnostics n_sarees = row_count;

    -- Keep who-was-added-when; drop the stock and sales history that no longer exists.
    delete from public.audit_events
     where action not in ('member_added', 'member_role_changed', 'member_removed');
    get diagnostics n_audit = row_count;

    if reset_numbering then
      update public.sku_counters set last_value = 0;
      delete from public.sale_counters where true;
    end if;

  elsif mode = 'drafts_and_voids' then
    delete from public.sale_items
     where sale_id in (select id from public.sales where status in ('draft', 'void'));
    get diagnostics n_items = row_count;
    delete from public.sales where status in ('draft', 'void');
    get diagnostics n_sales = row_count;
    n_sarees := 0;  -- stock is untouched: drafts never changed stock and voids put it back

  else
    raise exception 'NOT RUN. mode must be ''everything'' or ''drafts_and_voids'', got %', mode;
  end if;

  raise notice 'Deleted: % sale items, % sales, % sarees, % audit events (mode %, numbering reset %).',
    n_items, n_sales, n_sarees, n_audit, mode, (mode = 'everything' and reset_numbering);
end $$;

-- Result check: after mode 'everything' every count except members_kept should be 0.
select
  (select count(*) from public.sarees)                                   as sarees_left,
  (select count(*) from public.sales)                                    as sales_left,
  (select count(*) from public.sale_items)                               as sale_items_left,
  (select count(*) from public.business_members)                         as members_kept,
  (select last_value from public.sku_counters limit 1)                   as last_sku_number,
  (select count(*) from storage.objects where bucket_id = 'saree-photos') as photo_files_still_in_storage;
