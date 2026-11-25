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
# Absolute: simctl resolves the app's log paths itself (a relative one made every launch fail)
out="$(mkdir -p "$4" && cd "$4" && pwd)"
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
def model(name):
    # "iPhone 17 Pro" -> 17, "iPad Pro 13-inch (M5)" -> 13 and 5: the newest has the highest numbers
    return [int(n) for n in re.findall(r"\d+", name)]
for alternative in sys.argv[1].split("||"):
    matches = sorted((t for t in types if re.search(alternative, t["name"])), key=lambda t: model(t["name"]))
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
limit 180 xcrun simctl install "$udid" "$app" || { echo "::error::the app could not be installed"; exit 1; }
stamp "installed"
# German language and region for the whole simulator, like the community's devices (the app follows the device's
# region for dates and money; launch arguments for it were ignored)
limit 60 xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array de-DE || true
limit 60 xcrun simctl spawn "$udid" defaults write -g AppleLocale -string de_DE || true
# Right after booting, `simctl ui` and `status_bar` hang: the colour scheme goes through the app's own setting
# (Darstellung, agora.theme), the status bar is set now that the simulator has settled
limit 90 xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true

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
  shoot() {
    rm -f "$log"
    limit 20 xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
    SIMCTL_CHILD_AGORA_SHOT_STAGE="$stage" SIMCTL_CHILD_AGORA_SHOT_SERVER="$server" \
    SIMCTL_CHILD_AGORA_SHOT_EMAIL="$(account_email "$account")" SIMCTL_CHILD_AGORA_SHOT_PASSWORD="$password" \
    SIMCTL_CHILD_AGORA_SHOT_TAB="$tab" SIMCTL_CHILD_AGORA_SHOT_ROUTE="$route" SIMCTL_CHILD_AGORA_SHOT_PILL="$pill" \
      limit 60 xcrun simctl launch --terminate-running-process --stdout="$log" --stderr="$log" "$udid" "$bundle" \
        -agora.theme "$appearance" -AppleLanguages "(de-DE)" -AppleLocale de_DE >"$out/launch-$name.txt" 2>&1 \
      || echo "::warning::$name: launch failed: $(tr '\n' ' ' < "$out/launch-$name.txt")"
    # Until the driver says it is done (at most 40 s), then time for pictures and animations
    for _ in $(seq 1 80); do grep -q -e "AGORA_SHOT ready" -e "AGORA_SHOT failed" "$log" 2>/dev/null && break; sleep 0.5; done
    sleep 3
  }
  stamp "$name"
  shoot
  # A failed load (the very first sign-in on a fresh simulator can time out) gets a second try
  if ! grep -q "AGORA_SHOT ready" "$log" 2>/dev/null; then
    echo "::warning::$name: $(grep -h "AGORA_SHOT" "$log" 2>/dev/null | tail -1 || echo 'no answer from the app') – once more"
    shoot
  fi
  if ! grep -q "AGORA_SHOT ready" "$log" 2>/dev/null; then
    echo "::error::$name: $(grep -h "AGORA_SHOT" "$log" 2>/dev/null | tail -1 || echo 'no answer from the app')"
    failed=$((failed + 1))
  fi
  limit 30 xcrun simctl io "$udid" screenshot --type=png "$out/$name.png" >/dev/null 2>&1 || echo "::warning::$name: no screenshot"
  # A (nearly) blank picture is taken again after a moment: a page still sliding in, or one that stays empty
  if [ -f "$out/$name.png" ] && [ "$(stat -f%z "$out/$name.png" 2>/dev/null || stat -c%s "$out/$name.png")" -lt 80000 ]; then
    sleep 4
    limit 30 xcrun simctl io "$udid" screenshot --type=png "$out/$name.png" >/dev/null 2>&1 || true
    size="$(stat -f%z "$out/$name.png" 2>/dev/null || stat -c%s "$out/$name.png")"
    [ "$size" -lt 80000 ] && echo "::warning::$name: the screen is still (nearly) empty ($size bytes)"
  fi
done < "$here/shots.txt"

# Crash reports of the app (the simulator writes them to the Mac's reports folder)
crashes="$(find "$HOME/Library/Logs/DiagnosticReports" -iname "*Agora*" -newer "$app/Info.plist" 2>/dev/null)"
if [ -n "$crashes" ]; then
  echo "::error::the app crashed: $(echo "$crashes" | wc -l | tr -d ' ') crash report(s)"
  echo "$crashes" | while read -r report; do cp "$report" "$out/"; done
fi
echo "$failed problem(s)"
exit 0
