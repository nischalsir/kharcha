# Builds and publishes a Kharcha release.
#
# One version, read from pubspec.yaml, is used for everything: the Android
# versionName/versionCode, the Git tag, the release title and the file names.
# The app's update check reads the latest GitHub release, so publishing here
# is also what tells installed apps that an update exists.
#
# Usage:
#   .\tool\release.ps1 -Notes path\to\notes.md
#   .\tool\release.ps1 -Notes notes.md -SkipBuild     # reuse the last build
#
# Needs: flutter, gh (signed in), the Android SDK build-tools, and the release
# key (android/key.properties + the keystore it names). Nothing is published
# unless every check passes.
param(
  [Parameter(Mandatory = $true)][string]$Notes,
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $root

function Fail([string]$message) {
  Write-Host "release: $message" -ForegroundColor Red
  exit 1
}

# --- One version for everything ---------------------------------------------
$pubspec = Get-Content 'pubspec.yaml' -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
  Fail 'pubspec.yaml has no "version: x.y.z+n" line.'
}
$version = $Matches[1]
$build = $Matches[2]
# Releases are named the short way: v1.1 for 1.1.0, v1.3.1 as it is.
$tag = 'v' + ($version -replace '\.0$', '')

$appInfo = Get-Content 'lib\core\app_info.dart' -Raw
if ($appInfo -notmatch "version = '$([regex]::Escape($version))'" -or
    $appInfo -notmatch "buildNumber = '$build'") {
  Fail "lib/core/app_info.dart does not say $version / $build like pubspec.yaml."
}

if (-not (Test-Path -LiteralPath $Notes)) { Fail "Notes file not found: $Notes" }
if (-not (Test-Path 'android\key.properties')) {
  Fail 'android/key.properties is missing, so the build would be debug-signed.'
}

# --- The source being released is what is on GitHub -------------------------
$dirty = git status --porcelain --untracked-files=no
if ($dirty) { Fail 'There are uncommitted changes. Commit them first.' }
git fetch --quiet origin
$head = git rev-parse HEAD
$remote = git rev-parse 'origin/main'
if ($head -ne $remote) { Fail 'HEAD is not what is on origin/main. Push first.' }
$existing = git ls-remote --tags origin "refs/tags/$tag"
if ($existing) { Fail "Tag $tag already exists. Bump the version in pubspec.yaml." }

# --- Build -------------------------------------------------------------------
$apk = 'build\app\outputs\flutter-apk\app-release.apk'
$aab = 'build\app\outputs\bundle\release\app-release.aab'
if (-not $SkipBuild) {
  $started = Get-Date
  foreach ($target in @('apk', 'appbundle')) {
    Write-Host "release: building $target ..."
    # Run in a child shell: Gradle writes a harmless Java warning to stderr,
    # which would otherwise be treated as a failure here.
    & powershell -NoProfile -ExecutionPolicy Bypass -File 'tool\run.ps1' build $target | Out-Host
  }
  foreach ($file in @($apk, $aab)) {
    if (-not (Test-Path $file) -or (Get-Item $file).LastWriteTime -lt $started) {
      Fail "$file was not produced by this build."
    }
  }
}
foreach ($file in @($apk, $aab)) {
  if (-not (Test-Path $file)) { Fail "Missing $file. Run without -SkipBuild." }
}

# --- Check what was built ----------------------------------------------------
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
$tools = Get-ChildItem "$sdk\build-tools" -Directory | Sort-Object Name | Select-Object -Last 1
if (-not $tools) { Fail "No Android build-tools found under $sdk." }

$badging = & "$($tools.FullName)\aapt2.exe" dump badging $apk
$package = ($badging | Select-String '^package:').Line
if ($package -notmatch "name='com\.nischalpandey\.kharcha'") { Fail "Wrong application id: $package" }
if ($package -notmatch "versionName='$([regex]::Escape($version))'") { Fail "APK versionName is not ${version}: $package" }
if ($package -notmatch "versionCode='$build'") { Fail "APK versionCode is not ${build}: $package" }

if (-not $env:JAVA_HOME) {
  $jbr = 'C:\Program Files\Android\Android Studio\jbr'
  if (Test-Path $jbr) { $env:JAVA_HOME = $jbr }
}
# Through cmd: Java prints a harmless warning to stderr, which PowerShell
# would turn into a terminating error.
$certs = cmd /c "`"`"$($tools.FullName)\apksigner.bat`" verify --print-certs `"$apk`" 2>nul`""
$signer = ($certs | Select-String 'certificate DN').Line
if (-not $signer) { Fail 'The APK signature could not be verified.' }
if ($signer -match 'Android Debug') { Fail "The APK is debug-signed: $signer" }

# --- Publish -----------------------------------------------------------------
$out = Join-Path $env:TEMP "kharcha-release-$version"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$apkOut = Join-Path $out "kharcha-$tag.apk"
$aabOut = Join-Path $out "kharcha-$tag.aab"
Copy-Item $apk $apkOut -Force
Copy-Item $aab $aabOut -Force

Write-Host "release: publishing $tag ($version+$build)"
gh release create $tag $apkOut $aabOut --repo nischalsir/kharcha --target main `
  --title "Kharcha $tag" --notes-file $Notes --latest
if ($LASTEXITCODE -ne 0) { Fail 'gh could not create the release.' }

$assets = gh api "repos/nischalsir/kharcha/releases/tags/$tag" --jq '.assets[].name'
foreach ($name in @("kharcha-$tag.apk", "kharcha-$tag.aab")) {
  if ($assets -notcontains $name) { Fail "The release is missing $name." }
}
Write-Host "release: $tag published with $($assets -join ', ')" -ForegroundColor Green
Write-Host "release: $signer"
