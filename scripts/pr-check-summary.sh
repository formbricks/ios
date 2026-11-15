#!/usr/bin/env bash
# The gate behind the required `PR Check Summary` check: passes only when every job it needs
# succeeded. A job may be skipped instead only when its id is listed in ALLOWED_SKIPS (Sonar
# and E2E on fork PRs, which get no secrets). Failed, cancelled or unlisted skipped jobs fail.
#
# Usage: NEEDS='${{ toJSON(needs) }}' ALLOWED_SKIPS='sonarqube e2e-tests' scripts/pr-check-summary.sh
set -euo pipefail

: "${NEEDS:?NEEDS must hold the workflow needs context as JSON}"
allowed="${ALLOWED_SKIPS:-}"

jq -r --arg allowed "$allowed" '
  ($allowed | split(" ") | map(select(. != ""))) as $skippable
  | if length == 0 then "error: no jobs to judge" | halt_error(1) else . end
  | to_entries[]
  | .key as $job
  | .value.result as $result
  | (if $result == "success" then "ok"
     elif $result == "skipped" and ($skippable | index($job)) != null then "ok (skip allowed)"
     else "FAIL" end) as $verdict
  | "\($verdict)\t\($job)\t\($result)"
' <<<"$NEEDS" | {
  failed=0
  while IFS=$'\t' read -r verdict job result; do
    printf '%-18s %-20s %s\n' "$verdict" "$job" "$result"
    [[ "$verdict" == FAIL ]] && failed=1
  done
  exit "$failed"
}
