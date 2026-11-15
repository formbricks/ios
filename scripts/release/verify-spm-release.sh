#!/usr/bin/env bash
# Usage: verify-spm-release.sh <repo-url> <version>
#
# Verifies that <version> of the Swift package at <repo-url> is published:
#   1. polls `git ls-remote` until refs/tags/<version> exists, then
#   2. resolves exactly that version through SwiftPM from a scratch package,
#      the way a consumer's `.package(url:exact:)` would.
#
# Env:
#   VERIFY_TIMEOUT_SECONDS   how long to wait for the tag (default 600)
#   VERIFY_INTERVAL_SECONDS  delay between ls-remote polls (default 15)
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <repo-url> <version>" >&2
  exit 2
fi

repo_url="$1"
version="$2"
timeout="${VERIFY_TIMEOUT_SECONDS:-600}"
interval="${VERIFY_INTERVAL_SECONDS:-15}"

# 1. The tag is the release: wait until the remote serves it.
deadline=$((SECONDS + timeout))
until git ls-remote --exit-code --tags "$repo_url" "refs/tags/$version" >/dev/null; do
  if ((SECONDS >= deadline)); then
    echo "::error::Tag $version did not appear on $repo_url within ${timeout}s." >&2
    exit 1
  fi
  echo "Tag $version not on $repo_url yet; retrying in ${interval}s."
  sleep "$interval"
done
echo "Tag $version is live on $repo_url."

# 2. Resolve it the way a consumer does.
consumer="$(mktemp -d)"
trap 'rm -rf "$consumer"' EXIT
cat > "$consumer/Package.swift" <<SWIFT
// swift-tools-version:5.7
import PackageDescription

let package = Package(
  name: "ReleaseVerifier",
  dependencies: [
    .package(url: "$repo_url", exact: "$version")
  ]
)
SWIFT

if ! swift package --package-path "$consumer" --disable-dependency-cache resolve; then
  echo "::error::SwiftPM could not resolve $version from $repo_url." >&2
  exit 1
fi

resolved="$(jq -r '.pins[0].state.version // empty' "$consumer/Package.resolved")"
if [[ $resolved != "$version" ]]; then
  echo "::error::SwiftPM resolved '${resolved}' instead of $version from $repo_url." >&2
  exit 1
fi
echo "SwiftPM resolves $version from $repo_url."
