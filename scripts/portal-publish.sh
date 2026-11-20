#!/usr/bin/env bash
# Veröffentlicht das Developer Portal und wartet, bis die Veröffentlichung abgeschlossen ist.
# Aufruf: portal-publish.sh <APIM-Resource-ID>
set -euo pipefail

APIM_ID="${1:-}"
if [[ "$APIM_ID" != /subscriptions/* ]]; then
  echo "Aufruf: $0 <APIM-Resource-ID, beginnt mit /subscriptions/>" >&2
  exit 2
fi

REV="rev$(date -u +%Y%m%d%H%M%S)"
URL="https://management.azure.com${APIM_ID}/portalRevisions/${REV}?api-version=2022-08-01"

echo "Veröffentliche Portal-Revision ${REV} ..."
az rest --method put --url "$URL" \
  --headers "Content-Type=application/json" \
  --body '{"properties":{"description":"tofu publish","isCurrent":true}}' >/dev/null

DEADLINE=$(( $(date +%s) + 600 ))
while true; do
  RESP="$(az rest --method get --url "$URL")"
  STATUS="$(echo "$RESP" | jq -r '.properties.status // "unknown"')"
  case "$STATUS" in
    completed|Completed)
      echo "Portal veröffentlicht (${REV})."
      exit 0
      ;;
    failed|Failed)
      echo "Veröffentlichung fehlgeschlagen:" >&2
      echo "$RESP" | jq -r '.properties.statusDetails // .' >&2
      exit 1
      ;;
  esac
  if (( $(date +%s) > DEADLINE )); then
    echo "Zeitüberschreitung: Status nach 10 Minuten noch '${STATUS}'." >&2
    exit 1
  fi
  sleep 10
done
