#!/usr/bin/env bash
# Developer-Portal-Inhalte als Code, über Microsofts scripts.v3 (tools/portal-content/vendor).
#
#   scripts/portal-content.sh capture <apim-resource-id> <ordner>   # Instanz -> Snapshot
#   scripts/portal-content.sh apply   <apim-resource-id> <ordner>   # Snapshot -> Instanz (ersetzt!)
#
# capture: capture.js, danach data.json sortiert und eingerückt, damit Git-Diffs lesbar sind.
# apply:   cleanup.js + generate.js, also dasselbe wie migrate.js. Veröffentlicht NICHT,
#          das macht terraform_data.portal_publish (scripts/portal-publish.sh, mit Status-Abfrage).
set -euo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ $# -eq 3 ] || usage
mode="$1"; apim_id="$2"; folder="$3"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tools="$repo_root/tools/portal-content"
scripts="$tools/vendor/scripts.v3"

command -v node >/dev/null || { echo "node fehlt (Node.js 20 oder neuer)."; exit 1; }
command -v jq   >/dev/null || { echo "jq fehlt."; exit 1; }

# /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ApiManagement/service/<name>
IFS=/ read -r _ _ sub _ rg _ _ _ name <<<"$apim_id"
[ -n "${sub:-}" ] && [ -n "${rg:-}" ] && [ -n "${name:-}" ] || { echo "Ungültige APIM-Ressourcen-ID: $apim_id"; exit 1; }
args=(--subscriptionId "$sub" --resourceGroupName "$rg" --serviceName "$name")

# Abhängigkeiten genau nach package-lock.json installieren, falls sie fehlen oder veraltet sind.
if [ ! -d "$tools/node_modules" ] || [ "$tools/package-lock.json" -nt "$tools/node_modules/.package-lock.json" ]; then
  (cd "$tools" && npm ci --no-audit --no-fund --silent)
fi

mkdir -p "$folder"
folder="$(cd "$folder" && pwd)"

case "$mode" in
  capture)
    rm -rf "$folder/media"   # gelöschte Medien sollen nicht im Snapshot liegen bleiben
    (cd "$scripts" && node capture.js "${args[@]}" --folder "$folder")
    jq -S . "$folder/data.json" > "$folder/data.json.tmp" && mv "$folder/data.json.tmp" "$folder/data.json"
    echo "$(jq 'length' "$folder/data.json") Content Items, $(find "$folder/media" -type f ! -name '*.info' 2>/dev/null | wc -l | tr -d ' ') Medien-Dateien in $folder."
    ;;
  apply)
    [ -f "$folder/data.json" ] || { echo "$folder/data.json fehlt. Zuerst 'make portal-capture' ausführen."; exit 1; }
    (cd "$scripts" && node cleanup.js "${args[@]}")
    (cd "$scripts" && node generate.js "${args[@]}" --folder "$folder")
    ;;
  *) usage ;;
esac
