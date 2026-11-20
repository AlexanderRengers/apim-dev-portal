#!/usr/bin/env bash
# Prüft, ob das Developer Portal Inhalt hat (manueller Admin-Klick erledigt).
# Aufruf: portal-preflight.sh <APIM-Resource-ID>
set -euo pipefail

APIM_ID="${1:-}"
if [[ "$APIM_ID" != /subscriptions/* ]]; then
  echo "Aufruf: $0 <APIM-Resource-ID, beginnt mit /subscriptions/>" >&2
  exit 2
fi

URL="https://management.azure.com${APIM_ID}/contentTypes/page/contentItems?api-version=2022-08-01"

if ! OUT="$(az rest --method get --url "$URL" 2>&1)"; then
  echo "Abfrage fehlgeschlagen:" >&2
  echo "$OUT" >&2
  exit 1
fi

COUNT="$(echo "$OUT" | jq '.value | length')"
if [[ "$COUNT" -eq 0 ]]; then
  cat >&2 <<'MSG'
Developer Portal hat noch keinen Inhalt.
Bitte im Azure-Portal unter APIM -> Developer portal einmal im Admin-Modus öffnen
und danach 'make up-2' erneut ausführen.
MSG
  exit 1
fi

echo "Portal-Inhalt vorhanden (${COUNT} Seiten)."
