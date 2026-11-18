#!/usr/bin/env bash
# Prints an xcodebuild -destination for the unit tests: an iPhone simulator on the newest iOS
# runtime the selected Xcode can run, or any iOS simulator if there is no iPhone.
#
# On a fresh CI runner CoreSimulator can still be starting, and the first listings come back
# empty. So it asks `simctl` repeatedly with backoff (ATTEMPTS, RETRY_DELAY seconds, doubling
# to 30), then tries `xcodebuild -showdestinations` once. It fails, saying so, only after both.
#
# simctl also lists runtimes newer than the selected Xcode can run (macos-26 carries iOS 26.4 and
# 26.5 next to Xcode 26.3), so its runtimes are kept to the Xcode's own major.minor or older.
#
# Usage: scripts/simulator-destination.sh
# Test seams: SIMCTL_LIST_CMD, SHOW_DESTINATIONS_CMD, XCODE_VERSION_FOR_SIMULATORS.
set -euo pipefail

attempts="${ATTEMPTS:-6}"
delay="${RETRY_DELAY:-5}"
simctl_list="${SIMCTL_LIST_CMD:-xcrun simctl list devices available -j}"
show_destinations="${SHOW_DESTINATIONS_CMD:-xcodebuild -showdestinations -scheme ${SCHEME:-FormbricksSDK}}"
xcode_version="${XCODE_VERSION_FOR_SIMULATORS:-$(xcodebuild -version | sed -n 's/^Xcode //p')}"

# Rows are "<iPhone? 1|0>\t<OS>\t<name>\t<udid>"; the best one sorts first.
best() {
  LC_ALL=C sort -t$'\t' -k1,1nr -k2,2Vr -k3,3 | head -n 1 | cut -f4
}

from_simctl() {
  local json
  # A CoreSimulator that is still starting fails or prints no JSON: that is "not yet".
  json="$($simctl_list 2>/dev/null)" || return 0
  jq -e . >/dev/null 2>&1 <<<"$json" || return 0
  jq -r --arg xcode "$xcode_version" '
    def majmin: split(".") | map(tonumber) | .[0:2];
    (.devices // {}) | to_entries[]
    | select(.key | test("SimRuntime\\.iOS-[0-9-]+$"))
    | (.key | capture("iOS-(?<v>[0-9-]+)$").v | gsub("-"; ".")) as $os
    | select(($os | majmin) <= ($xcode | majmin))
    | .value[] | select(.isAvailable != false)
    | [(if (.deviceTypeIdentifier // "") | test("iPhone") then 1 else 0 end), $os, .name, .udid]
    | @tsv' <<<"$json"
}

from_xcodebuild() {
  # Destinations xcodebuild cannot use are listed after "Ineligible destinations".
  $show_destinations 2>/dev/null | sed '/Ineligible destinations/,$d' |
    sed -nE 's/.*\{ platform:iOS Simulator,.* id:([^,]+), OS:([0-9.]+), name:([^}]*[^ }]) *\}.*/\2\t\3\t\1/p' |
    awk -F'\t' '{ print ($2 ~ /iPhone/ ? 1 : 0) "\t" $0 }' || true
}

for ((attempt = 1; attempt <= attempts; attempt++)); do
  udid="$(from_simctl | best)"
  if [[ -n "$udid" ]]; then
    printf 'platform=iOS Simulator,id=%s\n' "$udid"
    exit 0
  fi
  if ((attempt < attempts)); then
    echo "simulator-destination: no iOS simulator listed yet (attempt $attempt/$attempts), retrying in ${delay}s" >&2
    sleep "$delay"
    delay=$((delay * 2 > 30 ? 30 : delay * 2))
  fi
done

udid="$(from_xcodebuild | best)"
if [[ -n "$udid" ]]; then
  printf 'platform=iOS Simulator,id=%s\n' "$udid"
  exit 0
fi

{
  echo "No iOS Simulator runtime for Xcode $xcode_version after $attempts attempts with simctl and one with xcodebuild."
  echo "Runtimes simctl lists:"
  xcrun simctl list runtimes 2>/dev/null | sed 's/^/  /' || true
  echo "Install one (Xcode > Settings > Components) or pass DESTINATION='platform=iOS Simulator,id=...'."
} >&2
exit 1
