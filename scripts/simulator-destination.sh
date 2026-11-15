#!/usr/bin/env bash
# Prints an xcodebuild -destination for the unit tests: an iPhone simulator (by name) on the
# newest iOS runtime the selected Xcode can run. It falls back to any iOS simulator, and fails with a clear
# message when there is none.
#
# It reads `xcodebuild -showdestinations` rather than `simctl list`, because simctl also lists
# runtimes newer than the selected Xcode supports, and xcodebuild would refuse them.
#
# Usage: scripts/simulator-destination.sh   (SHOW_DESTINATIONS_FILE=<file> reads saved output instead)
set -euo pipefail

if [[ -n "${SHOW_DESTINATIONS_FILE:-}" ]]; then
  destinations="$(cat "$SHOW_DESTINATIONS_FILE")"
else
  destinations="$(xcodebuild -showdestinations -scheme "${SCHEME:-FormbricksSDK}" 2>/dev/null || true)"
fi

# Only the eligible ones: xcodebuild lists runtimes it cannot use under "Ineligible destinations".
destinations="$(sed '/Ineligible destinations/,$d' <<<"$destinations")"

# One "<iPhone? 0|1>\t<OS>\t<name>\t<id>" row per concrete iOS Simulator destination.
candidates="$(
  sed -nE 's/.*\{ platform:iOS Simulator,.* id:([^,]+), OS:([0-9.]+), name:([^}]*[^ }]) *\}.*/\2\t\3\t\1/p' <<<"$destinations" |
    awk -F'\t' '{ print ($2 ~ /iPhone/ ? 1 : 0) "\t" $0 }'
)"

if [[ -z "$candidates" ]]; then
  {
    echo "No iOS Simulator runtime is available to $(xcode-select -p 2>/dev/null || echo 'the selected Xcode')."
    echo "Install one (Xcode > Settings > Components) or pass DESTINATION='platform=iOS Simulator,id=...'."
  } >&2
  exit 1
fi

# iPhones first, then the newest runtime (numeric per version component), then by name.
best="$(LC_ALL=C sort -t$'\t' -k1,1nr -k2,2Vr -k3,3 <<<"$candidates" | head -n 1)"
printf 'platform=iOS Simulator,id=%s\n' "$(cut -f4 <<<"$best")"
