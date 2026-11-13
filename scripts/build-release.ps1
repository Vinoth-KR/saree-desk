<#
  Builds the release APK(s) for Aadav Saree Desk.

  Usage (from the repo root, in PowerShell):
    .\scripts\build-release.ps1                 # analyze + test + ONE arm64 installer (recommended)
    .\scripts\build-release.ps1 -Universal      # one bigger APK that installs on any phone, incl. old 32-bit ones
    .\scripts\build-release.ps1 -SkipChecks     # skip analyze/test (not recommended for shipping)

  The default installer (arm64-v8a) runs on the Motorola moto g45 and the Samsung Galaxy S25 Ultra,
  and on practically every phone made in the last several years.

  Needs env.json (Supabase URL + publishable key). Signs with android\key.properties if it exists,
  otherwise with the DEBUG key (fine for a quick test, not for shipping). See RELEASE_GUIDE.md.
#>
param(
  [switch]$Universal,
  [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

# Use the persistent environment, with the D:\Dev layout as a fallback.
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { $env:Path = "D:\Dev\flutter\bin;$env:Path" }
if (-not $env:JAVA_HOME -and (Test-Path 'D:\Dev\jdk17')) { $env:JAVA_HOME = 'D:\Dev\jdk17' }
if (-not $env:ANDROID_HOME -and (Test-Path 'D:\Dev\android-sdk')) { $env:ANDROID_HOME = 'D:\Dev\android-sdk' }
if ($env:JAVA_HOME) { $env:Path = "$env:JAVA_HOME\bin;$env:Path" }
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'

function Step($text) { Write-Host "`n=== $text" -ForegroundColor Cyan }
function Fail($text) { Write-Host "`nFAILED: $text" -ForegroundColor Red; exit 1 }

if (-not (Test-Path 'env.json')) { Fail 'env.json is missing. Copy env.example.json to env.json and fill in your Supabase URL and publishable key.' }
$envText = Get-Content env.json -Raw
if ($envText -match 'YOUR-PROJECT-REF|YOUR-PUBLISHABLE') { Fail 'env.json still contains the example placeholder values.' }
if ($envText -match 'service_role|secret') { Fail 'env.json looks like it contains a secret key. Only the publishable (anon) key belongs in the app.' }

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$signed = Test-Path 'android\key.properties'
Step "Building version $version"
if ($signed) { Write-Host 'Signing: release keystore (android\key.properties)' -ForegroundColor Green }
else { Write-Host 'Signing: DEBUG key (android\key.properties not found). Do not ship this build.' -ForegroundColor Yellow }

Step 'flutter pub get'
flutter pub get | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'flutter pub get' }

if (-not $SkipChecks) {
  Step 'flutter analyze'
  flutter analyze
  if ($LASTEXITCODE -ne 0) { Fail 'analyzer reported problems' }
  Step 'flutter test'
  flutter test
  if ($LASTEXITCODE -ne 0) { Fail 'unit tests failed' }
}

# Flutter never clears old outputs, so stale files (for example 32-bit builds from an earlier run)
# would otherwise be picked up and copied to dist. Remove earlier release APKs first.
Get-ChildItem build\app\outputs\flutter-apk -Filter 'app-*release.apk*' -ErrorAction SilentlyContinue | Remove-Item -Force

Step 'flutter build apk --release'
$buildArgs = @('build', 'apk', '--release', '--dart-define-from-file=env.json')
if (-not $Universal) { $buildArgs += @('--split-per-abi', '--target-platform', 'android-arm64') }
flutter @buildArgs
if ($LASTEXITCODE -ne 0) { Fail 'flutter build failed' }

Step 'Output'
Get-ChildItem build\app\outputs\flutter-apk -Filter '*-release.apk' | ForEach-Object {
  $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.Substring(0, 16)
  '{0,-34} {1,7:N1} MB   sha256 {2}...' -f $_.Name, ($_.Length / 1MB), $hash
}
# Friendly copy for sharing: dist\AadavSareeDesk-<version>-<phone type>.apk
# dist\ is regenerated each run, so it only ever holds the current build.
New-Item -ItemType Directory -Force dist | Out-Null
Get-ChildItem dist -Filter 'AadavSareeDesk-*.apk' -ErrorAction SilentlyContinue | Remove-Item -Force
$verName = $version.Split('+')[0]
Get-ChildItem build\app\outputs\flutter-apk -Filter '*-release.apk' | ForEach-Object {
  $abi = $_.BaseName -replace '^app-', '' -replace '-release$', ''
  if ($abi -eq 'release') { $abi = 'universal' }
  Copy-Item $_.FullName "dist\AadavSareeDesk-$verName-$abi.apk" -Force
}
Write-Host "Installers copied to: $(Resolve-Path dist)" -ForegroundColor Green
if ($Universal) { Write-Host "`nUniversal installer: works on any Android 7.0+ phone." -ForegroundColor Green }
else { Write-Host "`nThis arm64-v8a installer runs on the Motorola moto g45 and the Samsung Galaxy S25 Ultra." -ForegroundColor Green }
if (-not $signed) { Write-Host 'Reminder: these APKs are debug-signed. Create a release keystore before shipping (RELEASE_GUIDE.md).' -ForegroundColor Yellow }
