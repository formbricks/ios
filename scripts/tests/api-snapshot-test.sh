#!/usr/bin/env bash
# Tests for scripts/api-snapshot.sh, against a hand-written symbol graph in fixtures/.
# Run: scripts/tests/api-snapshot-test.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
snapshot="$here/../api-snapshot.sh"
fixture="$here/fixtures/api-snapshot"
failures=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok - $name"
  else
    echo "not ok - $name"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/    /' || true
    failures=$((failures + 1))
  fi
}

actual="$("$snapshot" "$fixture")"

check "renders every public symbol, its conformances and its availability, in C-locale order" \
"Error.code: var code: Int
Widget.old: var old: Int [deprecated, renamed: spin(), message: Use spin().; iOS introduced 16.0]
Widget.spin(): func spin()
Widget: class Widget
Widget: conforms to Swift.Hashable
Widget: inherits from ObjectiveC.NSObject" \
"$actual"

check "leaves out doc comments and source locations" \
"" \
"$(grep -E 'Docs move|somewhere|line' <<<"$actual" || true)"

empty="$(mktemp -d)"
trap 'rm -rf "$empty"' EXIT
if "$snapshot" "$empty" >/dev/null 2>&1; then
  check "fails when the directory holds no symbol graph" "exit != 0" "exit 0"
else
  check "fails when the directory holds no symbol graph" "exit != 0" "exit != 0"
fi

exit "$failures"
