#!/usr/bin/env bash
# Usage: validate-tag.sh <tag> <prerelease>
#
# Exits 0 when <tag> is a plain SemVer 2.0.0 version (https://semver.org),
# for example 2.4.0 or 2.4.0-rc.1, and <prerelease> (the GitHub release's
# "Set as a pre-release" flag, "true" or "false") agrees with it: true
# exactly when the tag has a prerelease suffix. Exits 1 otherwise, including
# for a "v" prefix: Swift Package Manager consumers pin the bare version.
set -euo pipefail

tag="${1:-}"
prerelease="${2:-}"

# The SemVer 2.0.0 grammar, written as a POSIX extended regex.
num='(0|[1-9][0-9]*)'
ident='(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)'
semver="^${num}\.${num}\.${num}(-${ident}(\.${ident})*)?(\+[0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*)?$"

if [[ ! $tag =~ $semver ]]; then
  echo "::error::Tag '$tag' is not a plain semver version (expected MAJOR.MINOR.PATCH[-PRERELEASE], no 'v' prefix)." >&2
  exit 1
fi

if [[ "$prerelease" != true && "$prerelease" != false ]]; then
  echo "::error::The pre-release flag must be 'true' or 'false', got '$prerelease'." >&2
  exit 1
fi

# The prerelease suffix is everything after the first '-' in the part before any '+build'.
version="${tag%%+*}"
if [[ "$version" == *-* ]]; then tag_is_prerelease=true; else tag_is_prerelease=false; fi

if [[ "$prerelease" != "$tag_is_prerelease" ]]; then
  if [[ "$tag_is_prerelease" == true ]]; then
    echo "::error::Tag '$tag' is a prerelease, but the GitHub release is not marked as a pre-release." >&2
  else
    echo "::error::Tag '$tag' is a stable version, but the GitHub release is marked as a pre-release." >&2
  fi
  exit 1
fi

echo "Tag '$tag' is valid semver (prerelease: $prerelease)."
