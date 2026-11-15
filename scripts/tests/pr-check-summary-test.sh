#!/usr/bin/env bash
# Tests for scripts/pr-check-summary.sh, the gate behind the required `PR Check Summary` check.
# Run: scripts/tests/pr-check-summary-test.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
summary="$here/../pr-check-summary.sh"
failures=0

# Runs the summary with NEEDS / ALLOWED_SKIPS and reports "pass" or "fail".
verdict() {
  if NEEDS="$1" ALLOWED_SKIPS="$2" "$summary" >/dev/null 2>&1; then echo pass; else echo fail; fi
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

check "passes when every job succeeded" pass \
  "$(verdict '{"lint":{"result":"success"},"sonarqube":{"result":"success"}}' '')"

check "fails when a job failed" fail \
  "$(verdict '{"lint":{"result":"failure"},"sonarqube":{"result":"success"}}' '')"

check "fails when a job was cancelled" fail \
  "$(verdict '{"lint":{"result":"cancelled"}}' '')"

check "fails when a job was skipped without being allowed to" fail \
  "$(verdict '{"lint":{"result":"success"},"sonarqube":{"result":"skipped"}}' '')"

check "passes when only an allowed job was skipped" pass \
  "$(verdict '{"lint":{"result":"success"},"sonarqube":{"result":"skipped"}}' 'sonarqube e2e-tests')"

check "an allowed skip does not excuse that job failing" fail \
  "$(verdict '{"sonarqube":{"result":"failure"}}' 'sonarqube')"

check "an allowed skip for one job does not cover another" fail \
  "$(verdict '{"lint":{"result":"skipped"},"sonarqube":{"result":"skipped"}}' 'sonarqube')"

check "a job id that only contains an allowed id is not allowed" fail \
  "$(verdict '{"sonarqube-extra":{"result":"skipped"}}' 'sonarqube')"

check "fails when there are no jobs to judge" fail \
  "$(verdict '{}' '')"

report="$(NEEDS='{"lint":{"result":"success"},"build":{"result":"failure"}}' ALLOWED_SKIPS='' "$summary" 2>&1 || true)"
check "names the job that failed" yes "$(grep -q 'build.*failure' <<<"$report" && echo yes || echo no)"

exit "$failures"
