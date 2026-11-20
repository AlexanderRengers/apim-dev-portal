#!/usr/bin/env bash
# Checks that the developer portal has content (manual admin click done).
# Usage: portal-preflight.sh <APIM resource ID>
set -euo pipefail

APIM_ID="${1:-}"
if [[ "$APIM_ID" != /subscriptions/* ]]; then
  echo "Usage: $0 <APIM resource ID, starting with /subscriptions/>" >&2
  exit 2
fi

URL="https://management.azure.com${APIM_ID}/contentTypes/page/contentItems?api-version=2022-08-01"

if ! OUT="$(az rest --method get --url "$URL" 2>&1)"; then
  echo "Query failed:" >&2
  echo "$OUT" >&2
  exit 1
fi

COUNT="$(echo "$OUT" | jq '.value | length')"
if [[ "$COUNT" -eq 0 ]]; then
  cat >&2 <<'MSG'
The developer portal has no content yet.
Open it once in admin mode (Azure portal -> APIM -> Developer portal -> "Developer portal"),
then run 'make up-2' again.
MSG
  exit 1
fi

echo "Portal content present (${COUNT} pages)."
