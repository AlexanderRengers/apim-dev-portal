#!/usr/bin/env bash
# Publishes the developer portal and waits until publishing has completed.
# Usage: portal-publish.sh <APIM resource ID>
set -euo pipefail

APIM_ID="${1:-}"
if [[ "$APIM_ID" != /subscriptions/* ]]; then
  echo "Usage: $0 <APIM resource ID, starting with /subscriptions/>" >&2
  exit 2
fi

REV="rev$(date -u +%Y%m%d%H%M%S)"
URL="https://management.azure.com${APIM_ID}/portalRevisions/${REV}?api-version=2022-08-01"

echo "Publishing portal revision ${REV} ..."
az rest --method put --url "$URL" \
  --headers "Content-Type=application/json" \
  --body '{"properties":{"description":"tofu publish","isCurrent":true}}' >/dev/null

DEADLINE=$(( $(date +%s) + 600 ))
while true; do
  RESP="$(az rest --method get --url "$URL")"
  STATUS="$(echo "$RESP" | jq -r '.properties.status // "unknown"')"
  case "$STATUS" in
    completed|Completed)
      echo "Portal published (${REV})."
      exit 0
      ;;
    failed|Failed)
      echo "Publishing failed:" >&2
      echo "$RESP" | jq -r '.properties.statusDetails // .' >&2
      exit 1
      ;;
  esac
  if (( $(date +%s) > DEADLINE )); then
    echo "Timeout: status still '${STATUS}' after 10 minutes." >&2
    exit 1
  fi
  sleep 10
done
