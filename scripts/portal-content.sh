#!/usr/bin/env bash
# Developer portal content as code, via Microsoft's scripts.v3 (tools/portal-content/vendor).
#
#   scripts/portal-content.sh capture <apim-resource-id> <folder>   # instance -> snapshot
#   scripts/portal-content.sh apply   <apim-resource-id> <folder>   # snapshot -> instance (replaces!)
#
# capture: capture.js, then data.json is sorted and indented so git diffs stay readable.
# apply:   cleanup.js + generate.js, i.e. the same as migrate.js. Does NOT publish;
#          terraform_data.portal_publish does that (scripts/portal-publish.sh, with status polling).
set -euo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ $# -eq 3 ] || usage
mode="$1"; apim_id="$2"; folder="$3"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tools="$repo_root/tools/portal-content"
scripts="$tools/vendor/scripts.v3"

command -v node >/dev/null || { echo "node is missing (Node.js 20 or newer)."; exit 1; }
command -v jq   >/dev/null || { echo "jq is missing."; exit 1; }

# /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ApiManagement/service/<name>
IFS=/ read -r _ _ sub _ rg _ _ _ name <<<"$apim_id"
[ -n "${sub:-}" ] && [ -n "${rg:-}" ] && [ -n "${name:-}" ] || { echo "Invalid APIM resource ID: $apim_id"; exit 1; }
args=(--subscriptionId "$sub" --resourceGroupName "$rg" --serviceName "$name")

# Install dependencies exactly per package-lock.json if they are missing or outdated.
if [ ! -d "$tools/node_modules" ] || [ "$tools/package-lock.json" -nt "$tools/node_modules/.package-lock.json" ]; then
  (cd "$tools" && npm ci --no-audit --no-fund --silent)
fi

mkdir -p "$folder"
folder="$(cd "$folder" && pwd)"

case "$mode" in
  capture)
    rm -rf "$folder/media"   # media deleted in the portal must not linger in the snapshot
    (cd "$scripts" && node capture.js "${args[@]}" --folder "$folder")
    jq -S . "$folder/data.json" > "$folder/data.json.tmp" && mv "$folder/data.json.tmp" "$folder/data.json"
    echo "$(jq 'length' "$folder/data.json") content items, $(find "$folder/media" -type f ! -name '*.info' 2>/dev/null | wc -l | tr -d ' ') media files in $folder."
    ;;
  apply)
    [ -f "$folder/data.json" ] || { echo "$folder/data.json is missing. Run 'make portal-capture' first."; exit 1; }
    (cd "$scripts" && node cleanup.js "${args[@]}")
    (cd "$scripts" && node generate.js "${args[@]}" --folder "$folder")
    ;;
  *) usage ;;
esac
