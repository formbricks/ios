#!/usr/bin/env bash
# The gate behind the required `PR Check Summary` check: passes only when every job it needs
# succeeded, or was skipped where skipping is expected:
#   - sonarqube and e2e-tests on a PR from a fork, which gets no secrets;
#   - dependency-review on a push to main, where there is no diff to review.
# Anything else (a failure, a cancellation, or a skip outside those cases) fails it.
#
# Env: NEEDS_JSON (`toJSON(needs)`), EVENT_NAME (`github.event_name`),
#      IS_FORK_PR ("true" for a PR whose head lives in another repository).
# Tests: scripts/tests/pr-check-summary-test.sh
set -euo pipefail

: "${NEEDS_JSON:?NEEDS_JSON must hold the workflow needs context as JSON}"
: "${EVENT_NAME:?EVENT_NAME must hold github.event_name}"
is_fork_pr="${IS_FORK_PR:-false}"

allowed=()
if [[ "$EVENT_NAME" == pull_request && "$is_fork_pr" == true ]]; then
  allowed+=(sonarqube e2e-tests)
fi
if [[ "$EVENT_NAME" == push ]]; then
  allowed+=(dependency-review)
fi

jq -r --arg allowed "${allowed[*]-}" '
  ($allowed | split(" ") | map(select(. != ""))) as $skippable
  | if length == 0 then "error: no jobs to judge" | halt_error(1) else . end
  | to_entries[]
  | .key as $job
  | .value.result as $result
  | (if $result == "success" then "ok"
     elif $result == "skipped" and ($skippable | index($job)) != null then "ok (skip allowed)"
     else "FAIL" end) as $verdict
  | "\($verdict)\t\($job)\t\($result)"
' <<<"$NEEDS_JSON" | {
  failed=0
  while IFS=$'\t' read -r verdict job result; do
    printf '%-18s %-20s %s\n' "$verdict" "$job" "$result"
    [[ "$verdict" == FAIL ]] && failed=1
  done
  exit "$failed"
}
