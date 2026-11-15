#!/usr/bin/env bash
# Resolves FormbricksSDK the way an app does (over git, through Swift Package Manager, at a
# commit) into a scratch consumer, and builds the consumer for the iOS Simulator. Catches
# what the in-repo build cannot: files missing from git, a broken Package.swift, resources
# that only exist locally. Only committed changes are checked.
#
# Usage: scripts/package-check.sh [revision]   (default: HEAD)
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
revision="$(git -C "$repo" rev-parse "${1:-HEAD}")"

if [[ -n "$(git -C "$repo" status --porcelain -- Package.swift Sources)" ]]; then
  echo "package-check: uncommitted changes in Package.swift or Sources are not checked" >&2
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/formbricks-package-check.XXXXXX")"
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT
mkdir -p "$work/Consumer/Sources/Consumer"

# Served from a bare copy holding just this commit: SPM will not clone a worktree, and on CI
# the commit under test is a detached merge commit that no branch points at.
git init --quiet --bare "$work/formbricks-ios.git"
git -C "$repo" push --quiet "$work/formbricks-ios.git" "$revision:refs/heads/package-check"

cat >"$work/Consumer/Package.swift" <<SWIFT
// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Consumer",
    platforms: [.iOS(.v16)],
    products: [.library(name: "Consumer", targets: ["Consumer"])],
    dependencies: [
        .package(url: "file://$work/formbricks-ios.git", revision: "$revision")
    ],
    targets: [
        .target(
            name: "Consumer",
            dependencies: [.product(name: "FormbricksSDK", package: "formbricks-ios")]
        )
    ]
)
SWIFT

cat >"$work/Consumer/Sources/Consumer/Consumer.swift" <<'SWIFT'
import FormbricksSDK

public func startFormbricks() {
    let config = FormbricksConfig.Builder(appUrl: "https://app.formbricks.com", workspaceId: "workspace")
        .setLogLevel(.error)
        .build()
    Formbricks.setup(with: config)
    Formbricks.setUserId("user")
    Formbricks.track("action")
}
SWIFT

cd "$work/Consumer"
echo "package-check: resolving FormbricksSDK at $revision"
swift package resolve
# No warnings-as-errors here: SPM builds dependencies with warnings suppressed, and the two
# flags conflict. The `build` check covers warnings.
xcodebuild build \
  -scheme Consumer \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$work/DerivedData" \
  -quiet
echo "package-check: a consumer resolved and built FormbricksSDK at $revision"
