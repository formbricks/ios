#!/usr/bin/env bash
# Tests for scripts/pr-check-summary.sh, the gate behind the required `PR Check Summary` check.
# Run: scripts/tests/pr-check-summary-test.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
summary="$here/../pr-check-summary.sh"
failures=0

# verdict <needs JSON> <event name> <is fork PR>: runs the summary and prints "pass" or "fail".
verdict() {
  if NEEDS_JSON="$1" EVENT_NAME="$2" IS_FORK_PR="$3" "$summary" >/dev/null 2>&1; then
    echo pass
  else
    echo fail
  fi
}

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok - $name"
  else
    echo "not ok - $name: expected $expected, got $actual"
    failures=$((failures + 1))
  fi
}

all_green='{"lint":{"result":"success"},"sonarqube":{"result":"success"},"e2e-tests":{"result":"success"},"dependency-review":{"result":"success"}}'
no_secrets='{"lint":{"result":"success"},"sonarqube":{"result":"skipped"},"e2e-tests":{"result":"skipped"},"dependency-review":{"result":"success"}}'
no_dep_review='{"lint":{"result":"success"},"sonarqube":{"result":"success"},"e2e-tests":{"result":"success"},"dependency-review":{"result":"skipped"}}'

for event in pull_request merge_group push; do
  check "passes on $event when every job succeeded" pass "$(verdict "$all_green" "$event" false)"
done

check "fails when a job failed" fail \
  "$(verdict '{"lint":{"result":"failure"},"sonarqube":{"result":"success"}}' pull_request false)"

check "fails when a job was cancelled" fail \
  "$(verdict '{"lint":{"result":"cancelled"}}' pull_request false)"

# sonarqube and e2e-tests skip on fork PRs only: forks get no secrets.
check "a fork PR may skip sonarqube and e2e-tests" pass "$(verdict "$no_secrets" pull_request true)"
check "a same-repo PR may not skip sonarqube and e2e-tests" fail "$(verdict "$no_secrets" pull_request false)"
check "the merge queue may not skip sonarqube and e2e-tests" fail "$(verdict "$no_secrets" merge_group false)"
check "a push may not skip sonarqube and e2e-tests" fail "$(verdict "$no_secrets" push false)"
check "a fork flag outside pull_request allows no skip" fail "$(verdict "$no_secrets" merge_group true)"
check "a fork PR may not skip any other job" fail \
  "$(verdict '{"lint":{"result":"skipped"},"sonarqube":{"result":"skipped"}}' pull_request true)"
check "an allowed skip does not excuse that job failing" fail \
  "$(verdict '{"sonarqube":{"result":"failure"}}' pull_request true)"

# dependency-review skips on a push only: there is no base to compare against.
check "a push may skip dependency-review" pass "$(verdict "$no_dep_review" push false)"
check "a PR may not skip dependency-review" fail "$(verdict "$no_dep_review" pull_request false)"
check "a fork PR may not skip dependency-review" fail "$(verdict "$no_dep_review" pull_request true)"
check "the merge queue may not skip dependency-review" fail "$(verdict "$no_dep_review" merge_group false)"

check "a job id that only contains an allowed id is not allowed to skip" fail \
  "$(verdict '{"sonarqube-extra":{"result":"skipped"}}' pull_request true)"

check "fails when there are no jobs to judge" fail "$(verdict '{}' pull_request false)"

report="$(NEEDS_JSON='{"lint":{"result":"success"},"build":{"result":"failure"}}' EVENT_NAME=pull_request \
  IS_FORK_PR=false "$summary" 2>&1 || true)"
check "names the job that failed" yes "$(grep -q 'build.*failure' <<<"$report" && echo yes || echo no)"

exit "$failures"
