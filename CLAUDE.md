# Saree Desk: Claude Code implementation specification

## Product goal and non-goals
Build a PRIVATE, Android-first, native React Native inventory and sales application for exactly two trusted users (a husband and wife). It must index 100 sarees tonight and grow to 150+ items. Existing wholesale retail tags already contain the intended retail selling price, including the planned margin. Do NOT ask for cost price, profit margin, GSTIN, or supplier price. Never represent the markdown/discount as profit.

The user wants a native camera experience, Google sign-in, shared real-time stock, and easy corrections. Do not build public e-commerce, payment gateway, CRM, GST tax invoicing, elaborate role administration, generic warehouse software, or a website in v1. Prioritize usable running code over mockups.

## Preferred stack
- Expo-managed React Native, Expo Router, TypeScript, strict types.
- React Native components with a clean, accessible, touch-first UI. NativeWind optional; avoid styling-library setup delays if it blocks working flows.
- Supabase Postgres, Auth, Storage, and Realtime; @supabase/supabase-js.
- expo-image-picker for native camera/gallery; expo-image-manipulator for compression.
- expo-secure-store or the documented supported Supabase React Native session storage adapter; never store secrets in AsyncStorage. Check current Expo/Supabase documentation before choosing exact integration.
- expo-web-browser / Supabase Google OAuth with PKCE + application deep link for a development/internal build. Follow current official Expo/Supabase guidance. Do not claim native Google OAuth will work reliably in Expo Go. Provide email OTP or email/password testing fallback if Google Cloud configuration is not yet available, without bypassing authorization.
- expo-file-system, expo-sharing, expo-print for export/printing where supported; export UTF-8 CSV in first release. Use current Expo APIs rather than old deprecated methods.
- EAS internal APK build for Android. iOS can follow after Android works, with Apple provisioning caveats.
- No Vercel / Next.js server required for native v1.

## First-hour delivery contract
P0 (required to start indexing tonight): installable or runnable Android-first Expo app, login (Google if configured; otherwise secure temporary auth fallback), membership authorization, add saree with camera, search/list stock, duplicate-SKU prevention, add-next flow, backed by Supabase, edit and view photos, basic atomic sale and undo, basic CSV export. Test this end-to-end using actual Supabase.

P1 (complete next without redesign): multi-item draft sale with customer name, item price edits and one collective discount, preview/share a non-tax sales slip, richer dashboard, Realtime updates across two devices, barcode label CSV/PDF export. If time is tight, finish P0 and explicitly report P1 as pending. Do not fake working capabilities.

## App screens and user experience
1. Login: logo if available; Google sign-in; permitted testing fallback; show 'not authorized for this shop' if the authenticated user lacks membership.
2. Home: total items, available, sold, total collected; prominent 'Add saree' and 'New sale' buttons; recent sales; stock-age summary.
3. Add saree: minimal vertically compact form with fields below; camera/choose-photo; Save & add next (preserves receipt date and bill-index); Save & view. On save show SKU with copy button. Keep keyboard focus efficient.
4. Inventory: search box; Available/Sold/All filters, newest/oldest and inventory age; image tile; SKU, description, tagged price, receipt date. Tap row for larger photo, edit metadata, status and sale reference.
5. Sell: search available only by SKU, description (case-insensitive), marked price (exact or range); add to cart; show thumbnail/marked price; enter per-item negotiated price defaulting to marked price; optional customer name or explicitly 'Walk-in customer'; one order-level discount; preview; Confirm sale.
6. Sales: grouped sale list, customer, date, total, items, discounts, thumbnail previews; draft/confirmed/void filters. Open sale detail, share non-tax sales slip, Void/Undo sale with reason.
7. Tools/settings (can be a simple menu): export available inventory CSV, full inventory CSV, sales CSV, label-print CSV, database/backup instructions, sign out, app logo branding.

## Required inventory fields
- id UUID (database-generated)
- business_id UUID (to isolate this shop)
- sku unique within business, generated sequential visible identifier SR-0001, SR-0002 etc.; never reuse a SKU; server-side collision resistance and uniqueness, including multi-device adds. Allow manually entered SKU if it passes uniqueness. A UUID is the internal row ID, not the label ID.
- wholesale_receipt_date date, required, manually selected, defaults to last used value for the session.
- wholesale_bill_index text, required, prefilled with most recently used value for quick batch indexing.
- description text, required but short (e.g. 'Blue soft-silk floral border').
- image_path text, nullable so indexing does not block if image upload fails; support adding/replacing image later.
- marked_price_paise integer >0, required, based on existing original retail price tag; INR input converted to paise.
- status ('available' | 'sold'), default available; change ONLY through transactional sale/undo RPC.
- indexed_at timestamp, indexed_by user UUID; sold_at nullable.
Optional future fields not required now: fabric, color, source physical label, exhibition location.

A saree always represents ONE physical piece. Two identical designs require two SKUs. The original wholesaler's bill index is NOT the SKU. Inventory age = current date minus wholesale_receipt_date; also retain indexed_at for data quality.

## Sales and draft slips
- A sale may contain 1 or more UNIQUE available sarees.
- Sale has sale id UUID, generated human-readable number (e.g. SD-2026-000001), business_id, customer_name or 'Walk-in customer', created_by, created_at, confirmed_at, status (draft, confirmed, void), total_marked_paise, subtotal_negotiated_paise, order_discount_paise, total_collected_paise, void_reason, voided_at, voided_by.
- Sale item snapshots: saree_id, sku_at_sale, description_at_sale, marked_price_at_sale_paise, negotiated_price_paise, allocated_order_discount_paise, final_sold_price_paise. Preserve history when the inventory record is edited later.
- Display marked price and negotiated price separately. Default negotiated price = marked price. Allow per-item overrides and optional order-wide fixed discount. Do not invent cost or profit.
- Total marked = sum(marked snapshots); negotiated subtotal = sum(negotiated prices); total collected = negotiated subtotal - order discount, >= 0.
- Total customer discount vs tag = total marked - total collected.
- Allocate order discount proportionally to negotiated item prices in INTEGER PAISE; give remaining rounding paise to the last item. Confirm sum(final_sold_price_paise) == sale.total_collected_paise. Prevent negative line totals, duplicated SKUs, nonfinite or negative amounts.
- Save draft without changing stock. Two different drafts MAY reference the same available saree; no reservation yet. On CONFIRM, lock all saree rows deterministically, validate that every item is still available and belongs to the shop, write the sale and snapshots, set every selected saree sold, and record audit log in ONE DATABASE TRANSACTION. If any item unavailable, roll back everything and explain which SKU conflicts. Implement as a Postgres RPC invoked by Supabase, NOT a series of frontend calls.
- A one-item quick sale must use the same backend confirmation RPC to prevent race conditions.
- Realtime and query cache updates must remove sold pieces from available search immediately after success. Other devices receive Realtime changes and refetch; always revalidate at the server.
- Undo/void: owner or authorized editor must provide reason; lock affected rows and, in ONE transaction, void sale and set all affected sarees to available, preserve full history, record actor, time and reason. Refuse repeated undo. For a wrong item in a multi-item sale, void the whole sale and re-enter correctly in v1 (individual-item void can wait).
- A sales slip is an INTERNAL/provisional commercial record, not a GST tax invoice. Print/share header as 'Draft Sales Summary - Not a Tax Invoice' for drafts and 'Sales Record - Not a GST Tax Invoice' for confirmed sales. No GST breakdown, GSTIN or GST collection; do not imply these slips replace any legally required sale documentation. Confirm relevant business/invoicing obligations with a CA before selling.
- Customer name is used only for the intended sale record; phone/contact fields are NOT required. Minimize personal data and do not send customer details to analytics services.

## Database and data-access design
Use migrations in supabase/migrations/, with at least:
- businesses(id, name, created_at)
- business_members(business_id, user_id, role, created_at), composite PK and FKs, only two invited users. No open join/registration of a business.
- sarees (... fields above) and UNIQUE(business_id, sku), CHECK(marked_price_paise > 0), helpful indexes on business/status, receipt date, description and marked price.
- sales (... fields above) and UNIQUE(business_id, sale_number).
- sale_items(sale_id, saree_id, snapshots above), UNIQUE(sale_id, saree_id), FKs.
- audit_events(business_id, actor_user_id, action, entity_id, metadata, created_at).
- a server-side SKU number allocator and sale number allocator using PostgreSQL sequences or an atomic counter (not MAX(sku)+1 client side).

Enable RLS on EVERY exposed table. A Google-authenticated stranger must see zero stock. Membership controls read access to records within a business. Only owners can control membership. Do not store authorization roles in editable user_metadata. Avoid recursive membership RLS; use carefully designed security-definer helper if needed, with fixed search_path and explicit permissions.

All stateful changes (confirm_sale, void_sale, edit_saree_details, etc.) must be checked server-side for auth.uid() and business membership. Use robust SQL RPC transactions and deterministic row locking for checkout. Do not expose the Supabase service_role or other secret keys in the app. Never disable RLS to get the demo working. Test unauthorized and second-user access.

For first login, document a safe manual bootstrap in Supabase SQL Editor: after first permitted Google user signs in, look up their auth.users ID, create business, grant owner membership. After spouse signs in, manually grant editor/owner membership. Do not create an unrestricted public bootstrap that lets an unknown Google account claim the shop.

## Image capture and storage
- Capture using launchCameraAsync, allow choose from gallery; show preview before upload; request runtime permissions.
- Use expo-image-manipulator to resize long edge to ~1200px and JPEG compress roughly 0.65-0.75; aim < 500KB where possible. Avoid storing original 8MB camera photos in Supabase free storage.
- Store private images in Supabase Storage bucket 'saree-photos' using stable business/saree UUID folder path and unique filename per revision. Do not use a public bucket containing customer or sensitive data. Protect photo access using authenticated membership-based storage policies; use short-lived signed URLs for display.
- Upload should be retryable, and user can save text inventory even when a photo fails. Surface upload status and never pretend a photo is saved until its storage object exists.
- Storage path is stored in sarees.image_path. On replacing an image, update the reference; reclaim orphaned objects later.
- Photo backups are separate from CSV database export. Document how to download the complete photo bucket periodically.

## Search, realtime and dashboards
- Search available sarees by SKU (exact/prefix), description (case-insensitive substring), and integer marked price exact or range. 150 items is small; fetching one business and filtering locally is acceptable for v1, but never fetch data outside member RLS.
- Subscribe to Realtime changes on business sarees and sales tables. Include them in supabase_realtime publication. On change, invalidate/refetch inventory and KPIs; on reconnection/app foreground always refetch. Do not use realtime alone for checkout correctness.
- Dashboard cards: total indexed, available count, sold count, marked inventory retail value (NOT cost value), actual collected sales, total discount, average realized price. Date filters Today / This week / All time.
- Inventory-age buckets based on wholesale receipt date: 0-30, 31-60, 61-90, 90+ days; available inventory only. Sold list keeps original photos and price history.
- Sales by customer: customer name, order count, total collected, discount amount, most recent sale; warn that names alone are not unique identifiers. Do not claim reliable repeat-customer identification without a separately consented unique identifier.

## Barcode and export requirements
- Barcode symbology: Code 128. Barcode payload EXACTLY the SKU string, e.g. SR-0001. Do not encode price (price can change).
- Every saree detail screen should display SKU as readable text. Barcode label output must include SKU, abbreviated description, marked retail price, and brand logo if supplied.
- First priority: export UTF-8 CSV of stock (SKU, description, price, status, receipt date, bill index) and dedicated printer-label CSV (SKU/barcode_value, description, marked_price). Compatible with a desktop label-print workflow. Also export sales CSV with customer name, sale number, sale date, SKU, tagged price, final allocated sold price, discount, status.
- Next: generate correctly sized label PDFs in a Node desktop script using a proven Code128 renderer (e.g., bwip-js) and pdf-lib. Provide common 50x25mm and 50x30mm templates or user-configurable label width/height. Do not assume printer DPI, gap/roll configuration, command language, or Bluetooth support. Require a real test on the exact portable Seznik/other thermal printer before claiming compatibility.
- Expo Print can generate/share PDF sales slips. Direct BLE/USB printer integrations are out of scope for v1. Test label scanner readability with 4-6 real printed specimens before bulk printing.

## App branding
- User already has a logo. Use assets/brand/logo.png (or SVG converted to supported native asset) when provided. If absent, use a neutral temporary placeholder, NOT a generated business logo. Keep brand colors centralized in theme.ts.
- App icon and splash assets will be generated from user-supplied image when available; no copyrighted third-party logos.

## Errors, validation and safeguards
- Data must not disappear when navigation changes unexpectedly; preserve in-progress form locally until successful cloud save.
- Network required for durable save and sale confirmation in v1; show clear offline/error banner. Do not claim offline synchronization. Optional offline read cache can come later.
- Double-tapping Save/Confirm must not duplicate records. Implement idempotency key for confirm_sale (unique request token) or equivalent database guard; disable button during request but do not rely solely on button state.
- Reject duplicate SKU with friendly visible error; preserve form input.
- Confirm before void, and keep immutable audit events.
- Use INR formatting en-IN. Store money in integer paise. Avoid JavaScript float arithmetic for discounts.
- Don't leak secrets in debug logs. Use .env.example; actual .env is gitignored. Client uses only Supabase publishable key.
- Archive/no destructive deletes for customer sale records.

## Suggested project structure
app/(auth)/login.tsx
app/(tabs)/index.tsx
app/(tabs)/add.tsx
app/(tabs)/inventory.tsx
app/(tabs)/sell.tsx
app/(tabs)/sales.tsx
app/saree/[id].tsx
app/sale/[id].tsx
src/lib/supabase.ts
src/lib/auth.ts
src/lib/inventory.ts
src/lib/checkout.ts
src/lib/photos.ts
src/lib/format.ts
src/components/*
src/theme.ts
supabase/migrations/001_initial.sql
supabase/tests/*
scripts/generate-label-pdf.*
assets/brand/logo.png (only if user supplies)
.env.example
app.json or app.config.ts
eas.json
README_SETUP.md

## Required automated and manual tests
1. Add two sarees from same wholesale bill: date/index persists, SKU differs; photo opens on each details page.
2. Reject duplicate SKU, empty bill index, missing description and zero/negative marked price.
3. Search SKU/description/marked price; sold item disappears from sell search, but remains in 'Sold' inventory with image.
4. Create single-item sale tagged INR 2,499 sold for INR 2,199: discount INR 300; item becomes sold.
5. Create draft containing two items and one additional INR 300 collective discount; confirm: correct checkout math, consistent allocated final prices, both marked sold.
6. Simulate simultaneous checkout from two authorized clients with an overlapping SKU: EXACTLY ONE checkout succeeds; other fails cleanly with no partial sale/partial stock update.
7. Void confirmed sale with reason: all its items available, prior sale kept as VOID, original sale and void both in audit log. Repeated void is rejected.
8. Newly signed-in uninvited Google account cannot read inventory, photos or sales, even with copied Supabase URL/publishable key.
9. Two member accounts see stock updates after confirmation and can restart app without losing server-side records.
10. Export CSV opens correctly with the original SKU, bill index, marked price and sales history; no GSTIN/tax calculation invented.
11. Receipt date drives 30/60/90-day age buckets, not created_at.
12. Camera and gallery both work on Android device; permission denial is handled gracefully.

## Execution sequence (time-boxed)
0-10 min: Scaffold Expo Router app, install packages, create Supabase project/migrations/RLS and .env.example. If project credentials unavailable, document required input and continue UI with explicitly marked fixtures, not fake cloud success.
10-20 min: Auth wiring and authorization, app shell, shared UI components. Use temporary legitimate email OTP fallback if Google consent and redirect setup would delay indexing.
20-40 min: Add form, SKU allocation, photo capture/upload, save-and-next, inventory list/search/detail. Run on a real Android device with Expo Go where packages allow, then move to dev build for OAuth.
40-55 min: Quick sale, transactional confirm_sale RPC, simple undo, basic dashboard and CSV export.
55-60 min: Verify first real saree saved and visible after restart, photo accessible, sale undone, and export works. Explicitly list outstanding P1 work rather than blocking indexing.
After indexing begins: full draft cart with collective discount, saved draft, shareable sales slip, Realtime polish, barcode label PDF, second-user workflow, installable Android APK.

If an app can be built more quickly without NativeWind or a UI component library, prefer native StyleSheet. Do not swap the stack to Next.js or make a throwaway local-only data store. Work incrementally, run type checking/tests, and present concise status and exact commands when user intervention is required.

## Documentation links to consult during implementation
https://docs.expo.dev/guides/using-supabase/
https://supabase.com/docs/guides/auth/quickstarts/with-expo-react-native-social-sign-in
https://docs.expo.dev/versions/latest/sdk/imagepicker/
https://docs.expo.dev/versions/latest/sdk/imagemanipulator/
https://supabase.com/docs/guides/database/postgres/row-level-security
https://supabase.com/docs/guides/realtime/subscribing-to-database-changes
https://docs.expo.dev/build/internal-distribution/
https://docs.expo.dev/versions/latest/sdk/print/
https://supabase.com/pricing
