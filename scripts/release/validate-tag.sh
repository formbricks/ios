#!/usr/bin/env bash
# Usage: validate-tag.sh <tag>
#
# Exits 0 when <tag> is a plain SemVer 2.0.0 version (https://semver.org),
# for example 2.4.0 or 2.4.0-rc.1. Exits 1 otherwise, including for a
# "v" prefix: Swift Package Manager consumers pin the bare version.
set -euo pipefail

tag="${1:-}"

# The SemVer 2.0.0 grammar, written as a POSIX extended regex.
num='(0|[1-9][0-9]*)'
ident='(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)'
semver="^${num}\.${num}\.${num}(-${ident}(\.${ident})*)?(\+[0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*)?$"

if [[ ! $tag =~ $semver ]]; then
  echo "::error::Tag '$tag' is not a plain semver version (expected MAJOR.MINOR.PATCH[-PRERELEASE], no 'v' prefix)." >&2
  exit 1
fi

echo "Tag '$tag' is valid semver."
