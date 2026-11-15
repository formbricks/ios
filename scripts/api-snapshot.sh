#!/usr/bin/env bash
# Prints the public API recorded in a directory of Swift symbol graphs, one line per fact,
# sorted, with doc comments and source locations left out so the result only changes when
# the API does. `make api-dump` writes it to api/FormbricksSDK.api; `make api-check` diffs it.
#
# Usage: scripts/api-snapshot.sh <symbol-graph-dir>
set -euo pipefail

dir="${1:?usage: api-snapshot.sh <symbol-graph-dir>}"
shopt -s nullglob
graphs=("$dir"/*.symbols.json)
if [[ ${#graphs[@]} -eq 0 ]]; then
  echo "api-snapshot: no *.symbols.json in $dir" >&2
  exit 1
fi

jq -r -s '
  def version: [.major, .minor, .patch] | map(select(. != null) | tostring) | join(".");
  def availability:
    [ .[] | [
        .domain,
        (if .isUnconditionallyDeprecated then "deprecated" else empty end),
        (if .introduced then "introduced \(.introduced | version)" else empty end),
        (if .deprecated then "deprecated \(.deprecated | version)" else empty end),
        (if .obsoleted then "obsoleted \(.obsoleted | version)" else empty end),
        (if .renamed then "renamed: \(.renamed)" else empty end),
        (if .message then "message: \(.message)" else empty end)
      ]
      | if .[0] == "*" then .[1:] else [.[0] + " " + (.[1:] | join(", "))] end
      | join(", ")
    ] | join("; ");

  (map(.symbols[]) | map({key: .identifier.precise, value: (.pathComponents | join("."))}) | from_entries) as $paths
  | (
      (.[].symbols[]
        | "\(.pathComponents | join(".")): \(.declarationFragments | map(.spelling) | join(""))"
          + (if (.availability // []) | length > 0 then " [\(.availability | availability)]" else "" end)),
      (.[].relationships[]
        | select(.kind == "conformsTo" or .kind == "inheritsFrom")
        | select($paths[.source] != null)
        | "\($paths[.source]): \(if .kind == "conformsTo" then "conforms to" else "inherits from" end) \($paths[.target] // .targetFallback // .target)")
    )
' "${graphs[@]}" | LC_ALL=C sort -u
