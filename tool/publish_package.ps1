# Publishes a released version to GitHub Packages, so it shows under the
# repository's "Packages" as com.nischalpandey.kharcha.
#
# GitHub Packages has no Android app type, so the APK and the App Bundle go up
# as a Maven package. The files are taken from the GitHub Release of the same
# version, so the package is byte-for-byte what people download there.
#
# Usage:
#   .\tool\publish_package.ps1              # the version in pubspec.yaml
#
# Needs gh signed in with the write:packages scope:
#   gh auth refresh -h github.com -s write:packages
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $root

function Fail([string]$message) {
  Write-Host "package: $message" -ForegroundColor Red
  exit 1
}

$pubspec = Get-Content 'pubspec.yaml' -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
  Fail 'pubspec.yaml has no "version: x.y.z+n" line.'
}
$version = $Matches[1]
# Releases are named the short way: v1.1 for 1.1.0, v1.3.1 as it is.
$tag = 'v' + ($version -replace '\.0$', '')
$group = 'com.nischalpandey'
$artifact = 'kharcha'

$status = cmd /c 'gh auth status 2>&1'
if (-not ($status -match 'write:packages')) {
  Fail 'gh has no write:packages scope. Run: gh auth refresh -h github.com -s write:packages'
}
$token = gh auth token

$work = Join-Path $env:TEMP "kharcha-package-$version"
New-Item -ItemType Directory -Force -Path $work | Out-Null
gh release download $tag --repo nischalsir/kharcha --dir $work --clobber `
  --pattern "kharcha-$tag.apk" --pattern "kharcha-$tag.aab"
if ($LASTEXITCODE -ne 0) { Fail "Release $tag has no APK and AAB to publish." }

$pom = Join-Path $work "$artifact-$version.pom"
@"
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>$group</groupId>
  <artifactId>$artifact</artifactId>
  <version>$version</version>
  <packaging>apk</packaging>
  <name>Kharcha</name>
  <description>Kharcha, a Nepali expense tracker. Android app ($tag).</description>
  <url>https://github.com/nischalsir/kharcha</url>
</project>
"@ | Out-File -FilePath $pom -Encoding ascii

$base = "https://maven.pkg.github.com/nischalsir/kharcha/$($group -replace '\.', '/')/$artifact/$version"
$uploads = @(
  @{ File = $pom; Name = "$artifact-$version.pom" },
  @{ File = (Join-Path $work "kharcha-$tag.apk"); Name = "$artifact-$version.apk" },
  @{ File = (Join-Path $work "kharcha-$tag.aab"); Name = "$artifact-$version.aab" }
)
foreach ($upload in $uploads) {
  Write-Host "package: uploading $($upload.Name) ..."
  $code = curl.exe -sS -o NUL -w '%{http_code}' -u "nischalsir:$token" `
    -X PUT --upload-file $upload.File "$base/$($upload.Name)"
  if ($code -notmatch '^2') { Fail "$($upload.Name) was refused (HTTP $code)." }
}
Write-Host "package: ${group}.$artifact $version published" -ForegroundColor Green
