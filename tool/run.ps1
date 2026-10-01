# Launches the Kharcha app with the backend configuration from .env.
#
# The app reads its configuration from --dart-define values, and .env is the
# source of truth for those values, so the backend only works when the app is
# started through this script (or with the equivalent flags passed by hand).
#
# Usage:
#   .\tool\run.ps1                 # flutter run
#   .\tool\run.ps1 build apk       # any flutter build / test command
#   .\tool\run.ps1 run --release
param()

$ErrorActionPreference = 'Stop'

$envFile = Join-Path $PSScriptRoot '..\.env'
if (-not (Test-Path -LiteralPath $envFile)) {
  Write-Error "Missing $envFile. Copy .env.example to .env and fill the values."
}

$command = if ($args.Count -gt 0) { $args[0] } else { 'run' }
$rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }

# --dart-define must come after the full command path (e.g. "build apk"), and
# only commands that compile code accept it.
$acceptsDefines = $command -in @('run', 'test', 'drive') -or
  ($command -eq 'build' -and $rest.Count -gt 0 -and $rest[0] -notmatch '^--')

# Only these may be compiled into the client. Everything else in .env (the AI
# key, anything added later) must stay on the server: a --dart-define is baked
# into the binary and is trivially extractable from an APK or IPA.
$clientSafeKeys = @(
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'GOOGLE_SERVER_CLIENT_ID',
  'WEATHER_LAT',
  'WEATHER_LON'
)

$defines = @()
$skipped = @()
foreach ($line in [IO.File]::ReadAllLines($envFile)) {
  $match = [regex]::Match($line, '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$')
  if (-not $match.Success) { continue }
  $name = $match.Groups[1].Value
  $value = $match.Groups[2].Value.Trim().Trim('"', "'")
  if ($value.Length -eq 0) { continue }
  if ($name -notin $clientSafeKeys) {
    $skipped += $name
    continue
  }
  $defines += "--dart-define=$name=$value"
}

if ($skipped.Count -gt 0) {
  Write-Host "not sending to the client (server-side only): $($skipped -join ', ')"
}

if ($acceptsDefines -and $defines.Count -gt 0) {
  Write-Host "flutter $command with $($defines.Count) dart-define values from .env"
  $all = @($command) + $rest + $defines
  & flutter @all
} else {
  $all = @($command) + $rest
  & flutter @all
}