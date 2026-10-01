#!/usr/bin/env bash
# Launches the Kharcha app with the backend configuration from .env.
#
# Usage:
#   ./tool/run.sh                  # flutter run
#   ./tool/run.sh build apk        # any flutter build / test command
#   ./tool/run.sh run --release
set -euo pipefail

dir="$(cd "$(dirname "$0")/../" && pwd)"
env_file="$dir/.env"

if [[ ! -f "$env_file" ]]; then
  echo "Missing $env_file. Copy .env.example to .env and fill the values." >&2
  exit 1
fi

command="${1:-run}"
shift || true

# --dart-define must come after the full command path (e.g. "build apk"), and
# only commands that compile code accept it.
accepts_defines=0
case "$command" in
  run|test|drive) accepts_defines=1 ;;
  build) [[ "${1:-}" != --* ]] && accepts_defines=1 ;;
esac

# Only these may be compiled into the client. Everything else in .env (the AI
# key, anything added later) must stay on the server: a --dart-define is baked
# into the binary and is trivially extractable from an APK or IPA.
client_safe_keys=(
  SUPABASE_URL
  SUPABASE_ANON_KEY
  WEATHER_LAT
  WEATHER_LON
)

defines=()
skipped=()
if (( accepts_defines )); then
  while IFS= read -r line; do
    # Match KEY=value and drop anything that is not an assignment, rather than
    # splitting on '=' and hoping: a malformed line used to forward a blank
    # --dart-define to the client.
    [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]] || continue
    name="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    value="$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
    [[ -z "$value" ]] && continue
    if [[ ! " ${client_safe_keys[*]} " =~ " $name " ]]; then
      skipped+=("$name")
      continue
    fi
    defines+=("--dart-define=$name=$value")
  done < "$env_file"
fi

if (( ${#skipped[@]} > 0 )); then
  echo "not sending to the client (server-side only): ${skipped[*]}"
fi

if (( accepts_defines && ${#defines[@]} > 0 )); then
  echo "flutter $command with ${#defines[@]} dart-define values from .env"
  exec flutter "$command" "$@" "${defines[@]}"
else
  exec flutter "$command" "$@"
fi