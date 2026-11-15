#!/usr/bin/env bash
# Tests for validate-tag.sh. Run: bash scripts/release/test-validate-tag.sh
set -uo pipefail

script="$(cd "$(dirname "$0")" && pwd)/validate-tag.sh"
failures=0

expect_valid() {
  if ! out="$(bash "$script" "$1" 2>&1)"; then
    echo "FAIL: expected '$1' to be accepted, got: $out"
    failures=$((failures + 1))
  fi
}

expect_invalid() {
  if out="$(bash "$script" "$1" 2>&1)"; then
    echo "FAIL: expected '$1' to be rejected, got: $out"
    failures=$((failures + 1))
  fi
}

# Stable and prerelease versions ship.
expect_valid "2.4.0"
expect_valid "0.0.1"
expect_valid "10.20.30"
expect_valid "2.4.0-rc.1"
expect_valid "2.4.0-beta"
expect_valid "2.4.0-alpha.0.valid"
expect_valid "2.4.0+build.5"

# Anything else fails the release run.
expect_invalid "v2.4.0"
expect_invalid "V2.4.0"
expect_invalid ""
expect_invalid "2.4"
expect_invalid "2"
expect_invalid "2.4.0.1"
expect_invalid "02.4.0"
expect_invalid "2.04.0"
expect_invalid "2.4.0-"
expect_invalid "2.4.0-rc..1"
expect_invalid "2.4.0-01"
expect_invalid "2.4.0 "
expect_invalid "release-2.4.0"
expect_invalid $'2.4.0\n3.0.0'

if [[ $failures -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "validate-tag: all tests passed"
