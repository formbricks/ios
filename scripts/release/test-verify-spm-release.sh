#!/usr/bin/env bash
# Tests for verify-spm-release.sh against a local git repository that stands in
# for github.com/formbricks/ios. Needs git and a Swift toolchain.
# Run: bash scripts/release/test-verify-spm-release.sh
set -uo pipefail

script="$(cd "$(dirname "$0")" && pwd)/verify-spm-release.sh"
failures=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A minimal Swift package, tagged like a release, in a bare "remote".
make_remote() {
  local src="$work/src" remote="$work/remote.git"
  mkdir -p "$src/Sources/FormbricksSDK"
  cat > "$src/Package.swift" <<'SWIFT'
// swift-tools-version:5.7
import PackageDescription

let package = Package(
  name: "FormbricksSDK",
  products: [.library(name: "FormbricksSDK", targets: ["FormbricksSDK"])],
  targets: [.target(name: "FormbricksSDK")]
)
SWIFT
  echo 'public enum Formbricks {}' > "$src/Sources/FormbricksSDK/Formbricks.swift"
  git -C "$src" init -q -b main
  git -C "$src" -c user.name=test -c user.email=test@example.com add -A
  git -C "$src" -c user.name=test -c user.email=test@example.com commit -qm init
  git clone -q --bare "$src" "$remote"
  echo "$remote"
}

tag_remote() {
  local src="$work/src"
  git -C "$src" tag "$1"
  git -C "$src" push -q "$work/remote.git" "refs/tags/$1"
}

run_verify() {
  VERIFY_TIMEOUT_SECONDS="${TIMEOUT:-5}" VERIFY_INTERVAL_SECONDS=1 \
    bash "$script" "file://$remote" "$1" 2>&1
}

expect_fail() {
  if out="$(run_verify "$1")"; then
    echo "FAIL: expected '$1' to fail verification, got:"; echo "$out"
    failures=$((failures + 1))
  fi
}

expect_pass() {
  if ! out="$(run_verify "$1")"; then
    echo "FAIL: expected '$1' to verify, got:"; echo "$out"
    failures=$((failures + 1))
  fi
}

remote="$(make_remote)"
tag_remote "2.4.0"

expect_pass "2.4.0"

# The tag reaches the remote while the script is already polling.
(sleep 2 && tag_remote "2.5.0") &
TIMEOUT=20 expect_pass "2.5.0"
wait

# Prerelease tags resolve through `exact:` too.
tag_remote "2.7.0-rc.1"
expect_pass "2.7.0-rc.1"

# A tag that never appears fails once the timeout runs out.
TIMEOUT=2 expect_fail "9.9.9"

# The tag exists, but SPM cannot resolve it: the tagged commit has no manifest.
git -C "$work/src" rm -q Package.swift
git -C "$work/src" -c user.name=test -c user.email=test@example.com commit -qm "drop manifest"
tag_remote "2.6.0"
expect_fail "2.6.0"

if [[ $failures -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "verify-spm-release: all tests passed"
