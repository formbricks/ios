#!/usr/bin/env bash
# Tests for scripts/simulator-destination.sh, against `xcodebuild -showdestinations` output.
# Run: scripts/tests/simulator-destination-test.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
pick="$here/../simulator-destination.sh"
failures=0
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

# Prints the picked destination for the given -showdestinations output, or "error".
picked() {
  printf '%s\n' "$1" >"$work/destinations.txt"
  SHOW_DESTINATIONS_FILE="$work/destinations.txt" "$pick" 2>/dev/null || echo error
}

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok - $name"
  else
    echo "not ok - $name: expected '$expected', got '$actual'"
    failures=$((failures + 1))
  fi
}

placeholder='		{ platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }'

check "picks an iPhone on the newest runtime the Xcode can use" "platform=iOS Simulator,id=NEW-17" "$(picked "$placeholder
		{ platform:iOS Simulator, arch:arm64, id:OLD-16, OS:26.0, name:iPhone 16 }
		{ platform:iOS Simulator, arch:arm64, id:IPAD, OS:26.2, name:iPad (A16) }
		{ platform:iOS Simulator, arch:arm64, id:NEW-17, OS:26.2, name:iPhone 17 }
		{ platform:macOS, arch:arm64, id:MAC, name:My Mac }")"

check "compares runtime versions numerically, not as text" "platform=iOS Simulator,id=TEN" "$(picked "$placeholder
		{ platform:iOS Simulator, arch:arm64, id:NINE, OS:26.9, name:iPhone 17 }
		{ platform:iOS Simulator, arch:arm64, id:TEN, OS:26.10, name:iPhone 17 }")"

check "is stable when several iPhones share the newest runtime" "platform=iOS Simulator,id=A" "$(picked "$placeholder
		{ platform:iOS Simulator, arch:arm64, id:B, OS:26.2, name:iPhone Air }
		{ platform:iOS Simulator, arch:arm64, id:A, OS:26.2, name:iPhone 17 }")"

check "falls back to any iOS simulator when none is named iPhone" "platform=iOS Simulator,id=CUSTOM" "$(picked "$placeholder
		{ platform:iOS Simulator, arch:arm64, id:CUSTOM, OS:26.3.1, name:My Test Device }")"

check "ignores destinations xcodebuild lists as ineligible" "platform=iOS Simulator,id=OK" "$(picked "	Available destinations for the \"FormbricksSDK\" scheme:
$placeholder
		{ platform:iOS Simulator, arch:arm64, id:OK, OS:26.2, name:iPhone 17 }

	Ineligible destinations for the \"FormbricksSDK\" scheme:
		{ platform:iOS Simulator, arch:arm64, id:TOO-NEW, OS:26.5, name:iPhone 17, error:iOS 26.5 is not installed. }")"

check "prefers a device with iPhone anywhere in its name" "platform=iOS Simulator,id=MINE" "$(picked "$placeholder
		{ platform:iOS Simulator, arch:arm64, id:OTHER, OS:26.3.1, name:Crewfit QA }
		{ platform:iOS Simulator, arch:arm64, id:MINE, OS:26.3.1, name:Reel iPhone 17 Pro }")"

check "fails when only the placeholder is available" "error" "$(picked "$placeholder")"

message="$(printf '%s\n' "$placeholder" >"$work/destinations.txt"; SHOW_DESTINATIONS_FILE="$work/destinations.txt" "$pick" 2>&1 >/dev/null || true)"
check "explains the failure" yes "$(grep -q 'No iOS Simulator runtime' <<<"$message" && echo yes || echo no)"

exit "$failures"
