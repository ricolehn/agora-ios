#!/usr/bin/env bash
# Takes the screenshots of shots.txt on one simulator (macOS with Xcode). The app must be built for the simulator and a
# seeded test server must answer on http://localhost:3000 (start-server.sh, seed-server.mjs).
#
#   take.sh <Agora.app> <device type name regex> <light|dark> <output dir> [name filter regex]
#
# Writes <output dir>/<name>.png and app-<name>.log (the app's output), and copies crash reports of the app.
set -uo pipefail

app="$1"
device_regex="$2"
appearance="$3"
out="$4"
filter="${5:-.}"
here="$(cd "$(dirname "$0")" && pwd)"
bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
server="${AGORA_SERVER:-http://localhost:3000}"
password="${AGORA_PASSWORD:-Demo-Passwort-1}"
mkdir -p "$out"

# The newest iOS runtime and the first device type matching the regex
runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"] if r.get("platform") == "iOS" and r.get("isAvailable")]
rs.sort(key=lambda r: [int(p) for p in r["version"].split(".")])
print(rs[-1]["identifier"] if rs else "")')"
# Device types: alternatives separated by "||", tried in order; of the matches of one the newest (listed last)
devtype="$(xcrun simctl list devicetypes -j | python3 -c '
import json, re, sys
types = json.load(sys.stdin)["devicetypes"]
for alternative in sys.argv[1].split("||"):
    matches = [t for t in types if re.search(alternative, t["name"])]
    if matches:
        print(matches[-1]["identifier"] + "\t" + matches[-1]["name"]); break' "$device_regex")"
if [ -z "$runtime" ] || [ -z "$devtype" ]; then
  echo "::error::No iOS runtime or no device type matching '$device_regex'"
  xcrun simctl list runtimes; xcrun simctl list devicetypes | grep -i -e iphone -e ipad
  exit 1
fi
echo "Runtime $runtime, device $(echo "$devtype" | cut -f2), $appearance"

# Runs a command with a time limit (macOS has no `timeout`): a simulator command that hangs must not stop the run
limit() {
  local seconds="$1"; shift
  "$@" & local pid=$!
  ( sleep "$seconds"; kill -9 "$pid" 2>/dev/null && echo "::warning::timed out after ${seconds}s: $*" ) & local watchdog=$!
  wait "$pid"; local status=$?
  kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
  return $status
}
stamp() { echo "[$(date -u +%H:%M:%S)] $*"; }

udid="$(xcrun simctl create "Agora shots" "$(echo "$devtype" | cut -f1)" "$runtime")"
trap 'limit 60 xcrun simctl shutdown "$udid" >/dev/null 2>&1; limit 60 xcrun simctl delete "$udid" >/dev/null 2>&1' EXIT
stamp "booting $udid"
limit 60 xcrun simctl boot "$udid"
limit 300 xcrun simctl bootstatus "$udid" -b >/dev/null
stamp "booted"
limit 30 xcrun simctl ui "$udid" appearance "$appearance"
limit 30 xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
limit 180 xcrun simctl install "$udid" "$app" || { echo "::error::the app could not be installed"; exit 1; }
stamp "installed"

account_email() {
  case "$1" in
    admin) echo "admin@demo.agora" ;; member) echo "mitglied@demo.agora" ;; treasurer) echo "kasse@demo.agora" ;;
    events) echo "events@demo.agora" ;; mentor) echo "mentor@demo.agora" ;; mentoring) echo "mentoring@demo.agora" ;;
    *) echo "" ;;
  esac
}
trim() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<"$1"; }

failed=0
while IFS='|' read -r name account stage tab route pill; do
  name="$(trim "$name")"
  case "$name" in ''|\#*) continue ;; esac
  [[ "$name" =~ $filter ]] || continue
  account="$(trim "$account")"; stage="$(trim "$stage")"; tab="$(trim "$tab")"; route="$(trim "$route")"; pill="$(trim "$pill")"
  log="$out/app-$name.log"
  stamp "$name"
  limit 20 xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
  SIMCTL_CHILD_AGORA_SHOT_STAGE="$stage" SIMCTL_CHILD_AGORA_SHOT_SERVER="$server" \
  SIMCTL_CHILD_AGORA_SHOT_EMAIL="$(account_email "$account")" SIMCTL_CHILD_AGORA_SHOT_PASSWORD="$password" \
  SIMCTL_CHILD_AGORA_SHOT_TAB="$tab" SIMCTL_CHILD_AGORA_SHOT_ROUTE="$route" SIMCTL_CHILD_AGORA_SHOT_PILL="$pill" \
    limit 60 xcrun simctl launch --terminate-running-process --stdout="$log" --stderr="$log" "$udid" "$bundle" \
      -AppleLanguages "(de)" -AppleLocale de_DE >/dev/null
  # Until the driver says it is done (at most 40 s), then time for pictures and animations
  for _ in $(seq 1 80); do grep -q -e "AGORA_SHOT ready" -e "AGORA_SHOT failed" "$log" 2>/dev/null && break; sleep 0.5; done
  sleep 3
  if ! grep -q "AGORA_SHOT ready" "$log" 2>/dev/null; then
    echo "::warning::$name: $(grep -h "AGORA_SHOT" "$log" 2>/dev/null | tail -1 || echo 'no answer from the app')"
    failed=$((failed + 1))
  fi
  if ! limit 20 xcrun simctl spawn "$udid" launchctl list 2>/dev/null | grep -q "$bundle"; then
    echo "::error::$name: the app is not running any more (crash?)"
    failed=$((failed + 1))
  fi
  limit 30 xcrun simctl io "$udid" screenshot --type=png "$out/$name.png" >/dev/null 2>&1 || echo "::warning::$name: no screenshot"
done < "$here/shots.txt"

# Crash reports of the app (the simulator writes them to the Mac's reports folder)
find "$HOME/Library/Logs/DiagnosticReports" -name "*Agora*" -newer "$app/Info.plist" -exec cp {} "$out/" \; 2>/dev/null || true
echo "$failed problem(s)"
exit 0
