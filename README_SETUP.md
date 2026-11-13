# Aadav Saree Desk: setup guide (Flutter + Supabase)

Android-first Flutter app for two trusted users. Supabase is the source of truth (Postgres, Auth, Storage, Realtime).
No cost, profit or GST fields exist anywhere. Sales slips are internal records, not tax invoices.

## 1. Install the Flutter toolchain on Windows (no Android Studio needed)

You need three things: a JDK (17), the Flutter SDK, and the Android SDK command-line tools.
Install to a drive with space (examples use `D:\Dev`).

1. **JDK 17.** Download the Microsoft Build of OpenJDK 17 zip from https://learn.microsoft.com/java/openjdk/download and unzip it to `D:\Dev\jdk17`.
2. **Flutter.** `git clone --depth 1 -b stable https://github.com/flutter/flutter.git D:\Dev\flutter`
3. **Android command-line tools.** Download "Command line tools only" for Windows from https://developer.android.com/studio#command-line-tools-only and unzip so that this file exists:
   `D:\Dev\android-sdk\cmdline-tools\latest\bin\sdkmanager.bat`
4. **Environment variables** (PowerShell, user scope; open a new terminal afterwards):
   ```powershell
   [Environment]::SetEnvironmentVariable('JAVA_HOME','D:\Dev\jdk17','User')
   [Environment]::SetEnvironmentVariable('ANDROID_HOME','D:\Dev\android-sdk','User')
   $p = [Environment]::GetEnvironmentVariable('Path','User')
   [Environment]::SetEnvironmentVariable('Path', "$p;D:\Dev\flutter\bin;D:\Dev\jdk17\bin;D:\Dev\android-sdk\platform-tools",'User')
   ```
5. **SDK packages and licenses:**
   ```powershell
   sdkmanager --sdk_root=D:\Dev\android-sdk "platform-tools" "platforms;android-36" "build-tools;36.0.0"
   flutter config --android-sdk D:\Dev\android-sdk
   flutter doctor --android-licenses
   flutter doctor -v
   ```
   Package versions drift. If a build asks for a different platform or build-tools version, Gradle downloads it automatically once licenses are accepted.
6. **Windows Developer Mode** (needed for plugin symlinks): `start ms-settings:developers` and turn it on.
7. **Phone:** Settings > About phone > tap "Build number" 7 times > Developer options > enable USB debugging. Connect by USB and accept the prompt. `adb devices` should list it.

The only thing you lose without Android Studio is the emulator. Test on the real phone.

## 2. Supabase project

1. Create a new project at https://supabase.com (free tier is fine; note the one-week inactivity pause and lack of automatic backups).
2. **Project Settings > API:** copy the **Project URL** and the **publishable (anon) key**. Never use the `service_role` / secret key in the app.
3. **SQL Editor:** paste and run `supabase/migrations/001_initial.sql` (once).
4. **Email + password login (used tonight).** The built-in Supabase email service cannot edit templates, so there is no email-code flow.
   - Authentication > Users > Add user > Create new user: enter the email and a strong password, tick **Auto Confirm User**. Do this for both people.
   - Authentication > Sign In / Providers: turn **off** "Allow new users to sign up" so strangers cannot create accounts.
5. **Authentication > URL Configuration > Redirect URLs:** add `com.aadav.sareedesk://login-callback`.
6. **Google sign-in** (optional for tonight, email code works without it):
   - Google Cloud Console > APIs & Services > OAuth consent screen (External, add both users as test users) > Credentials > Create OAuth client ID > **Web application**.
   - Authorized redirect URI: the callback URL shown in Supabase under Authentication > Providers > Google (`https://<project>.supabase.co/auth/v1/callback`).
   - Paste the client ID and secret into the Supabase Google provider and enable it.
   - The app uses the browser-based PKCE flow with the deep link above. It works in a built APK (not tied to Expo Go).
7. **Bootstrap the two users** (no public way to join the shop):
   1. Create the users in the dashboard (step 4). They do not need to sign in first.
   2. Open `supabase/bootstrap.sql` in the SQL Editor, replace the email placeholders, and run steps 2 and 4.
   3. Run step 3 for the spouse once their user exists.
8. Storage bucket `saree-photos` (private) and its membership-based policies are created by the migration.
9. Realtime: the migration adds `sarees` and `sales` to the `supabase_realtime` publication.

## 3. Configure and run the app

```powershell
copy env.example.json env.json      # then edit env.json with your URL and publishable key
flutter pub get
flutter run --dart-define-from-file=env.json     # phone connected by USB
```

`env.json` is gitignored. Only the publishable key goes in it.

## 4. Build an installable APK

```powershell
flutter build apk --release --dart-define-from-file=env.json
# output: build\app\outputs\flutter-apk\app-release.apk
```

Copy the APK to the phone (USB, Drive, or `adb install -r <apk>`) and allow "Install unknown apps". It is signed with the debug key, which is fine for internal use between two phones. Updates must use the same build machine/key or you must uninstall first.

## 5. Logo

Place your logo at `assets/brand/logo.png`. Until then a neutral placeholder icon is shown. Colors are in `lib/core/theme.dart`.

## 6. Tests

- Dart unit tests (money, discount allocation, search, CSV, age): `flutter test`
- Database tests (RLS lockout, duplicate SKU, atomic conflict, void, allocation): run `supabase/tests/rls_and_rpc_tests.sql` in the SQL Editor. It rolls back and leaves no data. The two-tab race instructions are at the bottom of that file.

## 7. Backups and caveats

- CSV (Tools screen) backs up text records only. Download the `saree-photos` bucket from Supabase Storage periodically for photos.
- Network is required to save or confirm a sale. There is no offline sync. If a photo upload fails the text record is saved and the photo is kept on the phone for retry (Inventory banner).
- Sales slips are "Not a GST Tax Invoice". Confirm your obligations with a CA.
- Labels use a QR code whose payload is exactly the SKU. Print and scan 4 to 6 specimens on your actual label printer before printing all labels.

## 8. Run the migrations in order

Run each file once in the Supabase SQL Editor, in this order:

1. `supabase/migrations/001_initial.sql`
2. `supabase/migrations/002_drafts_and_roles.sql` (drafts edited in place, discard draft, owner/editor/viewer roles, team management)
3. `supabase/migrations/003_delete_saree.sql` (the Delete stock button in the app)

Optional: `supabase/cleanup_replaced_drafts.sql` previews, and can delete, the void rows that older versions created when a draft was edited. Run its step 1 and look at the rows before using step 2.

## 9. Roles

| Role | Can do |
|---|---|
| owner | Everything, including the Team and roles screen (Tools menu) |
| editor | Add and edit stock, sell, void sales |
| viewer | View only |

Roles are stored in `business_members` and enforced by the database, not just hidden in the app. The owner adds people, changes roles and removes people in Tools > Team and roles. A person must already have an account (see Google sign-in below, or create them in Supabase > Authentication > Users). The last owner cannot be demoted or removed.

## 10. Google sign-in

The app already has the Google button, the PKCE flow and the deep link. You only configure Google and Supabase.

1. **Google Cloud Console** (https://console.cloud.google.com): create a project, for example "Aadav Saree Desk".
2. **APIs & Services > OAuth consent screen**: User type External. App name, your support email. Leave it in **Testing** and add every person who will sign in (you and your spouse) under **Test users**. No verification is needed for two test users.
3. **APIs & Services > Credentials > Create credentials > OAuth client ID**: Application type **Web application**.
   Authorized redirect URI: `https://<your-project-ref>.supabase.co/auth/v1/callback`
   Copy the **Client ID** and **Client secret**.
4. **Supabase > Authentication > Sign In / Providers > Google**: enable it and paste the client ID and secret. Save.
5. **Supabase > Authentication > URL Configuration**: add `com.aadav.sareedesk://login-callback` to Redirect URLs (already done if you followed section 2).
6. In the app tap **Sign in with Google**. The browser opens, you pick the account, and you return to the app.

Notes:
- A Google user can sign in only if their email matches an existing Supabase user, or if "Allow new users to sign up" is on. With sign-ups off, create each person once in Authentication > Users (Auto Confirm) using their Google email, then add them in Team and roles. If Google sign-in is still refused with sign-ups off, turn sign-ups on temporarily: RLS means a stranger who signs up still sees nothing until the owner adds them.
- The secret never goes in the app. Only the Supabase publishable key does.
- Keep passwords for the email and password login in a password manager. You can keep both login methods.

## 11. Scanning and label codes (QR)

Labels use **QR codes**. The payload is exactly the SKU, for example `SR-0001`, never the price, so a price change never makes a printed label wrong.

- The saree detail screen shows the QR code for that SKU.
- The Sell screen has a scan button. It reads QR codes with the phone camera and adds each available saree to the sale. Sold, unknown and already-added codes are rejected with a message.
- Tools > "Export QR label data (CSV)" gives `qr_value, description, marked_price` for every available saree. `qr_value` is the SKU text; load it into your label software and render it as a QR code.

Why QR for phones: a phone camera reads QR from any angle and distance, QR error correction tolerates a smudged label, and a 7-character SKU makes a small, coarse QR that stays crisp on a 50x25 mm thermal label. Test 4 to 6 real printed labels on your actual printer before printing all of them.

## 12. Clearing test data (before real indexing)

Use this once, after testing and before you start entering your real stock. **It cannot be undone**, and free-tier Supabase projects have no automatic backup, so export anything you want to keep first (Tools in the app, the CSV exports).

What it removes: all stock, all sales (confirmed, void and drafts) and their line items. What it keeps: the shop, the people and their roles.

1. **Preview.** In the Supabase SQL Editor run `supabase/maintenance/1_preview_counts.sql`. It only reads. Check the shop name and that the counts are what you expect to delete.
2. **Wipe.** Open `supabase/maintenance/2_wipe_test_data.sql` and edit the three settings at the top:
   - `confirm_phrase`: change `'change me'` to exactly `'DELETE TEST DATA'`. Until you do, the script refuses to run.
   - `mode`: `'everything'` (stock and all sales) or `'drafts_and_voids'` (only drafts and void sales; stock and confirmed sales stay).
   - `reset_numbering`: `true` makes the next saree `SR-0001` and the next sale `SD-<year>-000001` again. Only use it before you have printed any real labels, because SKU numbers are handed out again.

   Run the whole file. Supabase may ask you to confirm a destructive query. The result row at the end should show 0 for `sarees_left`, `sales_left` and `sale_items_left`, with your people still counted in `members_kept`.
3. **Photos.** The script does not delete photo files, because current Supabase blocks deleting storage records with SQL. In the dashboard open Storage, `saree-photos`, open the folder, select everything and delete it. Skip this step if you only used `drafts_and_voids`.
4. **Phones.** A photo that was still waiting to upload for a wiped saree is dropped the next time you tap **Retry upload** in Stock. Pull down to refresh Stock and Home.

## 13. Deleting one stock entry in the app

Open Stock, tap the saree, scroll to the bottom and tap **Delete stock**, then confirm. Owners and editors can do this; viewers cannot.

A saree can be deleted only if it has **never been in any sale**. If it appears in a confirmed, void or draft sale the app explains why and shows no button, because sales history is never destroyed. For a draft, discard or edit the draft first. The SKU number is not handed out again, and the photo file stays in storage (the audit log records its path so you can clean up in the Storage dashboard).
