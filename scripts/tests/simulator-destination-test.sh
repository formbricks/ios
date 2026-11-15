#!/usr/bin/env bash
# Tests for scripts/simulator-destination.sh. The simulator list and `xcodebuild -showdestinations`
# are replaced by fake commands that print fixtures, so no simulator is needed.
# Run: scripts/tests/simulator-destination-test.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
pick="$here/../simulator-destination.sh"
failures=0
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok - $name"
  else
    echo "not ok - $name: expected '$expected', got '$actual'"
    failures=$((failures + 1))
  fi
}

# `simctl list devices available -j` output for "<runtime>|<device type>|<name>|<udid>" rows.
devices_json() {
  printf '%s\n' "$@" | jq -R -s '
    split("\n") | map(select(. != "") | split("|"))
    | reduce .[] as [$r, $t, $n, $u] ({devices: {}};
        .devices["com.apple.CoreSimulator.SimRuntime." + $r] += [{
          name: $n, udid: $u, isAvailable: true,
          deviceTypeIdentifier: ("com.apple.CoreSimulator.SimDeviceType." + $t)
        }])'
}

# Writes an executable named $1 that prints $2, and prints its path.
fake() {
  printf '%s\n' "$2" >"$work/$1.out"
  printf '#!/usr/bin/env bash\ncat %q\n' "$work/$1.out" >"$work/$1"
  chmod +x "$work/$1"
  echo "$work/$1"
}

# The picker run against an Xcode 26.3 with the given simctl and -showdestinations output.
run_pick() {
  local simctl="$1" showdest="$2" attempts="$3"
  SIMCTL_LIST_CMD="$simctl" SHOW_DESTINATIONS_CMD="$showdest" \
    XCODE_VERSION_FOR_SIMULATORS=26.3 RETRY_DELAY=0 ATTEMPTS="$attempts" "$pick"
}

# Prints the picked destination, or "error".
picked() {
  run_pick "$(fake simctl "$1")" "$(fake showdest "${2:-}")" 2 2>/dev/null || echo error
}

no_devices='{"devices": {}}'
placeholder='		{ platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }'

# simctl, the primary source.

check "picks an iPhone on the newest runtime the Xcode can run" "platform=iOS Simulator,id=NEW-17" "$(picked "$(devices_json \
  'iOS-26-0|iPhone-16|iPhone 16|OLD-16' \
  'iOS-26-2|iPad-A16|iPad (A16)|IPAD' \
  'iOS-26-2|iPhone-17|iPhone 17|NEW-17')")"

check "skips runtimes newer than the selected Xcode" "platform=iOS Simulator,id=SUPPORTED" "$(picked "$(devices_json \
  'iOS-26-2|iPhone-17|iPhone 17|SUPPORTED' \
  'iOS-26-5|iPhone-17|iPhone 17|TOO-NEW')")"

check "accepts a patch runtime of the Xcode's own version" "platform=iOS Simulator,id=PATCH" "$(picked "$(devices_json \
  'iOS-26-3|iPhone-17-Pro|Crewfit QA|PATCH')")"

check "compares runtime versions numerically, not as text" "platform=iOS Simulator,id=TWO" "$(picked "$(devices_json \
  'iOS-9-3|iPhone-6s|iPhone 6s|NINE' \
  'iOS-26-2|iPhone-17|iPhone 17|TWO')")"

check "knows an iPhone by its device type, whatever its name" "platform=iOS Simulator,id=PHONE" "$(picked "$(devices_json \
  'iOS-26-2|iPad-A16|iPad (A16)|TABLET' \
  'iOS-26-2|iPhone-17|My Test Device|PHONE')")"

check "is stable when several iPhones share the newest runtime" "platform=iOS Simulator,id=A" "$(picked "$(devices_json \
  'iOS-26-2|iPhone-Air|iPhone Air|B' \
  'iOS-26-2|iPhone-17|iPhone 17|A')")"

check "ignores watchOS and tvOS runtimes" "error" "$(picked "$(devices_json \
  'watchOS-26-2|Apple-Watch|Apple Watch|WATCH')")"

# Waiting for CoreSimulator: on a fresh runner the first listings can come back empty.

printf '0' >"$work/count"
devices_json 'iOS-26-2|iPhone-17|iPhone 17|LATE' >"$work/ready.json"
cat >"$work/slow-simctl" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$work/count") + 1 ))
printf '%s' "\$n" >"$work/count"
if (( n < 3 )); then echo '$no_devices'; else cat "$work/ready.json"; fi
EOF
chmod +x "$work/slow-simctl"
check "retries until the simulators are listed" "platform=iOS Simulator,id=LATE" \
  "$(run_pick "$work/slow-simctl" "$(fake showdest "")" 5 2>/dev/null || echo error)"

# xcodebuild -showdestinations, the fallback when simctl never lists one.

check "falls back to xcodebuild's eligible destinations" "platform=iOS Simulator,id=OK" "$(picked "$no_devices" \
  "	Available destinations for the \"FormbricksSDK\" scheme:
$placeholder
		{ platform:iOS Simulator, arch:arm64, id:OK, OS:26.2, name:iPhone 17 }

	Ineligible destinations for the \"FormbricksSDK\" scheme:
		{ platform:iOS Simulator, arch:arm64, id:TOO-NEW, OS:26.5, name:iPhone 17, error:iOS 26.5 is not installed. }")"

check "prefers an iPhone among xcodebuild's destinations" "platform=iOS Simulator,id=MINE" "$(picked "$no_devices" \
  "$placeholder
		{ platform:iOS Simulator, arch:arm64, id:OTHER, OS:26.3.1, name:Crewfit QA }
		{ platform:iOS Simulator, arch:arm64, id:MINE, OS:26.3.1, name:Reel iPhone 17 Pro }")"

# Giving up.

check "fails when neither source lists a simulator" "error" "$(picked "$no_devices" "$placeholder")"

message="$(run_pick "$(fake simctl "$no_devices")" "$(fake showdest "$placeholder")" 3 2>&1 >/dev/null || true)"
check "says how often it tried before failing" yes \
  "$(grep -q 'No iOS Simulator runtime.*after 3 attempts' <<<"$message" && echo yes || echo no)"

exit "$failures"
