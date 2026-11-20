#!/usr/bin/env bash
# Sets the developer portal's sign-up setting (email/password registration) on an APIM instance.
# Entra ID sign-in is not affected: new Entra users still get the one-time "Complete sign up" form.
# Usage: portal-signup.sh <APIM resource ID> <true|false>
set -euo pipefail

APIM_ID="${1:-}"
ENABLED="${2:-}"
if [[ "$APIM_ID" != /subscriptions/* || ( "$ENABLED" != "true" && "$ENABLED" != "false" ) ]]; then
  echo "Usage: $0 <APIM resource ID, starting with /subscriptions/> <true|false>" >&2
  exit 2
fi

URL="https://management.azure.com${APIM_ID}/portalsettings/signup?api-version=2022-08-01"
BODY="{\"properties\":{\"enabled\":${ENABLED},\"termsOfService\":{\"enabled\":false,\"consentRequired\":false}}}"

az rest --method put --url "$URL" --headers "Content-Type=application/json" "If-Match=*" --body "$BODY" >/dev/null
ACTUAL="$(az rest --method get --url "$URL" --query properties.enabled -o tsv)"
if [[ "$ACTUAL" != "$ENABLED" ]]; then
  echo "Sign-up setting is '$ACTUAL', expected '$ENABLED'." >&2
  exit 1
fi
echo "Portal sign-up (email/password registration) enabled=$ENABLED."
