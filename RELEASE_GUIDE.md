# Aadav Saree Desk: release guide

How to build the Android APK, ship it to the phones, and update it later.

Set up the toolchain first (`README_SETUP.md`, section 1) and have a working `env.json`.

## What you are shipping

- **One installer**: `dist\AadavSareeDesk-<version>-arm64-v8a.apk` (about 27 MB). It runs on the **Motorola moto g45** and the **Samsung Galaxy S25 Ultra**, and on practically every phone made in the last several years. Only very old 32-bit phones need the universal build (`-Universal`, below).
- The APK contains your Supabase **URL and publishable key**. That is by design and safe, because the database enforces access with row-level security. It must **never** contain a `service_role` or secret key. The build script refuses to run if `env.json` looks like it has one.
- App data (stock, photos, sales) lives in Supabase, not on the phone. Reinstalling the app loses only small local things: unsent photo retries and unsaved form text.

## One-time: create your release signing key

Android only lets you update an installed app with an APK signed by the **same key**. Until you create your own key, release builds are signed with a debug key from this computer, which is fine for a test but not for shipping.

1. Create the keystore **outside the repository**. `keytool` ships with the JDK. In PowerShell:
   ```powershell
   New-Item -ItemType Directory -Force D:\Dev\keys | Out-Null
   & "$env:JAVA_HOME\bin\keytool.exe" -genkeypair -v -keystore D:\Dev\keys\aadav-release.jks `
     -alias aadav -keyalg RSA -keysize 2048 -validity 10000
   ```
   It asks for a keystore password, a key password (press Enter to reuse the keystore password), and your name and organization details. Choose a strong password and put it in a password manager.

2. Create `android\key.properties` (gitignored, never commit it):
   ```properties
   storePassword=YOUR_KEYSTORE_PASSWORD
   keyPassword=YOUR_KEY_PASSWORD
   keyAlias=aadav
   storeFile=D:/Dev/keys/aadav-release.jks
   ```
   Use forward slashes in `storeFile`.

3. **Back up `aadav-release.jks` and its passwords** somewhere safe and separate from this computer (password manager plus a cloud drive or USB stick). If you lose the key you can still build new APKs, but phones that already have the app must uninstall it before they can install one signed with a new key. Your cloud data is not affected.

## Every release

1. **Bump the version** in `pubspec.yaml`:
   ```yaml
   version: 1.0.1+2     # name+buildNumber
   ```
   The number after `+` must go **up** with every release, otherwise Android refuses to install it over the old one.
2. **Run the database migrations** that this version needs (`README_SETUP.md`, section 8) before the new app reaches the phones.
3. **Build:**
   ```powershell
   .\scripts\build-release.ps1
   ```
   If Windows says running scripts is disabled, use this instead (it changes no system setting):
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\build-release.ps1
   ```
   It checks `env.json`, runs `flutter analyze` and `flutter test`, builds, then lists the APKs with size and checksum. The finished installer is in `dist\`, for example `dist\AadavSareeDesk-1.0.1-arm64-v8a.apk`. `dist\` is cleared and refilled on every run, so it only ever holds the current build. Send that one file.
   Manual equivalent:
   ```powershell
   flutter build apk --release --split-per-abi --target-platform android-arm64 --dart-define-from-file=env.json
   ```
   - The default build is arm64-only. Add `-Universal` to the script only if someone has an old 32-bit phone; it is about three times bigger.
   - Pick one style (arm64 or universal) and keep using it. The two use different internal version codes, so switching can block an update-in-place.
4. **Check the APK on a real phone before sending it on** (see the checklist below).

### Release checklist

- [ ] Installs on the phone; the app opens on the login screen.
- [ ] Sign in works (email and password, and Google if configured).
- [ ] Add saree with a **camera photo**, save, and see it in Stock with the photo.
- [ ] Scan a QR label in Sell; sell it; void it; the saree is available again.
- [ ] Save a draft, edit it, discard another.
- [ ] A viewer account cannot add or sell.
- [ ] Dark and light theme and the accent color both look right.
- [ ] Export a CSV from Tools and open it.

## Before the first install: remove the test (debug) build

**Do this once on every phone that already has a test build, such as the Motorola g45 right now.** Test builds are signed with a throwaway debug key. The release installer is signed with your own key, so Android refuses to install it over the test build and says "App not installed". The two builds have the same name, icon and package, so you cannot tell them apart by looking. If the phone has Aadav Saree Desk and you did not install it from `dist\`, remove it.

**Before you remove it:**
- Open Stock. If a **"photo not uploaded"** banner shows, tap **Retry upload** until it clears. Those photos exist only on the phone and are lost on uninstall.
- Everything else (stock, sales, users, photos already uploaded) lives in Supabase and is not lost.
- You sign in again. Small local settings (theme, accent color, last-used receipt date and bill index) may reset.

**Method 1: on the phone**
1. Long-press the **Aadav Saree Desk** icon on the home screen or in the app drawer, then tap **App info**. (Or open Settings, Apps, Aadav Saree Desk.)
2. Tap **Uninstall**, then **OK**.
3. Install the release file (next section).

**Method 2: from the computer** (phone connected by USB with USB debugging on)
```powershell
adb devices
adb uninstall com.aadav.aadav_saree_desk
```
`adb devices` should list the phone, and `adb uninstall` should print `Success`. If it prints anything else, use Method 1 instead, and check that `adb devices` shows the right phone.

On a **new phone, or a phone with no earlier test build**, skip this section.

You only do this once. After the release build is installed, every future update installs over the top and keeps the login.

## Installing on a phone

**Option A: USB cable** (developer phone)
```powershell
adb devices
adb install -r dist\AadavSareeDesk-1.0.1-arm64-v8a.apk
```
`-r` replaces an existing install and keeps its data.

**Option B: send the file** (your spouse's phone)
1. Send the file from `dist\` (`AadavSareeDesk-<version>-arm64-v8a.apk`) through Google Drive, WhatsApp "document", email, or copy it over USB.
2. On the phone, open the file. Android asks to allow "Install unknown apps" for the app you opened it from (Files, Drive, Chrome). Allow it for that one app.
3. If Google Play Protect says the app is from an unrecognized developer, tap **More details**, then **Install anyway**. This is expected for an app that is not on the Play Store.
4. Open the app and sign in with that person's own account. They need to be added first by the owner under Tools, Team and roles.

You can turn "Install unknown apps" back off afterwards.

## Updating

Build with a higher `+number` and the **same signing key**, then install over the old one (Option A with `-r`, or Option B on the phone). Login and data are kept.

If the phone still has a **test (debug) build**, follow "Before the first install: remove the test (debug) build" above first. Updates only install over a build signed with the same key.

## Changing the Supabase project or key

The URL and key are baked in at build time. If either changes, update `env.json`, bump the version, rebuild, and reinstall.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| "App not installed" | Signed with a different key than the installed app (uninstall first), or the build number is not higher, or the phone is out of storage. |
| Samsung phone says the install is blocked (Auto Blocker) | Samsung's **Auto Blocker** (Settings, Security and privacy) blocks apps from outside the stores. Turn it off for the install, then you can turn it back on. |
| "There was a problem parsing the package" | The file was cut off in transfer. Compare the sha256 printed by the script with the received file (`Get-FileHash`). |
| Build stops with `Could not close incremental caches` | The project and Flutter's package cache are on different drives. Already handled by `kotlin.incremental=false` in `android/gradle.properties`. |
| Build stops on a download error | Flaky network. Run the script again; Gradle resumes from its cache. |
| Script says `WARNING: android/key.properties not found` | The build is debug-signed. Create the release key (above) before shipping. |
| App opens to "Supabase is not configured" | Built without `env.json`. Always build with the script or `--dart-define-from-file=env.json`. |
| Google button opens the browser but does not return | The redirect URL `com.aadav.sareedesk://login-callback` is missing from Supabase Authentication, URL Configuration. |

## Not covered

- Play Store publishing (needs a Play Console account and an app bundle, `flutter build appbundle`).
- iOS (needs a Mac and an Apple developer account).
