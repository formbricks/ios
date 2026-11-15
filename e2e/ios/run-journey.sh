#!/usr/bin/env bash
# Builds and runs the XCUITest golden journey in Playground/ on an iPhone simulator.
#   e2e/ios/run-journey.sh build   build-for-testing, then boot the simulator (no server needed)
#   e2e/ios/run-journey.sh test    test-without-building against the server at E2E_APP_URL
# Env for `test`: E2E_APP_URL (https://, for example the tunnel), E2E_USER_ID, E2E_FEEDBACK,
# optional E2E_WORKSPACE_ID. Optional: DESTINATION (default: scripts/simulator-destination.sh).
# A failed journey is retried once (-retry-tests-on-failure -test-iterations 2). The result bundle
# is .build/e2e/GoldenJourney.xcresult.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${root}"
derived_data=".build/e2e"
result_bundle="${derived_data}/GoldenJourney.xcresult"
destination="${DESTINATION:-$(scripts/simulator-destination.sh)}"
xcodebuild_args=(
  -project Playground/Playground.xcodeproj
  -scheme Playground
  -destination "${destination}"
  -derivedDataPath "${derived_data}"
)

case "${1:-}" in
  build)
    echo "==> Building the playground and its UI tests for ${destination}" >&2
    xcodebuild build-for-testing "${xcodebuild_args[@]}" SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
    # Boot now so the journey does not pay for it while the tunnel is open.
    if [[ "${destination}" =~ id=([A-Za-z0-9-]+) ]]; then
      xcrun simctl boot "${BASH_REMATCH[1]}" 2>/dev/null || true
      xcrun simctl bootstatus "${BASH_REMATCH[1]}" -b >/dev/null
    fi
    ;;
  test)
    : "${E2E_APP_URL:?set E2E_APP_URL to the server https URL}"
    : "${E2E_USER_ID:?}" "${E2E_FEEDBACK:?}"
    # xcodebuild hands TEST_RUNNER_<name> to the UI test runner as <name>.
    export TEST_RUNNER_E2E_APP_URL="${E2E_APP_URL}"
    export TEST_RUNNER_E2E_USER_ID="${E2E_USER_ID}"
    export TEST_RUNNER_E2E_FEEDBACK="${E2E_FEEDBACK}"
    export TEST_RUNNER_E2E_WORKSPACE_ID="${E2E_WORKSPACE_ID:-clsdkqaws00000000000000001}"
    rm -rf "${result_bundle}"
    echo "==> Running the golden journey against ${E2E_APP_URL} on ${destination}" >&2
    xcodebuild test-without-building "${xcodebuild_args[@]}" \
      -resultBundlePath "${result_bundle}" \
      -retry-tests-on-failure -test-iterations 2
    ;;
  *)
    echo "usage: $0 build|test" >&2
    exit 2
    ;;
esac
