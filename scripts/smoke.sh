#!/usr/bin/env bash
# Smoke-Test der Customers API über das APIM-Gateway.
# Eingaben: GATEWAY_URL, SMOKE_KEY (Umgebungsvariablen). Exit 0 = alles grün, 1 = mindestens ein Fehler.
set -uo pipefail

if [[ -z "${GATEWAY_URL:-}" || -z "${SMOKE_KEY:-}" ]]; then
  echo "GATEWAY_URL und SMOKE_KEY müssen gesetzt sein." >&2
  exit 2
fi

BASE="${GATEWAY_URL%/}/crm/customers"
HOST="${GATEWAY_URL#https://}"; HOST="${HOST%%/*}"
PORTAL_ORIGIN="https://${HOST%%.azure-api.net}.developer.azure-api.net"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0

# req METHOD URL [BODY] [mit_key:1|0] [weitere curl-Argumente...]
# Setzt STATUS, BODY (Datei $TMP/body), Header in $TMP/headers.
req() {
  local method="$1" url="$2" body="${3:-}" withkey="${4:-1}"
  shift 4 2>/dev/null || shift $#
  local args=(-s -o "$TMP/body" -D "$TMP/headers" -w '%{http_code}' -X "$method" "$url")
  [[ "$withkey" == "1" ]] && args+=(-H "Ocp-Apim-Subscription-Key: $SMOKE_KEY")
  [[ -n "$body" ]] && args+=(-H "Content-Type: application/json" --data-binary "$body")
  STATUS="$(curl "${args[@]}" "$@")"
}

check() { # name, condition-result (0 = ok), detail
  if [[ "$2" == "0" ]]; then
    echo "PASS $1"
  else
    echo "FAIL $1 ($3)"
    FAILS=$((FAILS + 1))
  fi
}
skip() { echo "SKIP $1 (create fehlgeschlagen)"; FAILS=$((FAILS + 1)); }
body() { cat "$TMP/body"; }
header() { grep -i "^$1:" "$TMP/headers" | head -1 | cut -d' ' -f2- | tr -d '\r'; }

# Warten auf die Rollenzuweisung: nur bei 403 wiederholen, höchstens 10 Minuten.
DEADLINE=$(( $(date +%s) + 600 ))
while true; do
  req GET "$BASE" "" 1
  [[ "$STATUS" != "403" ]] && break
  if (( $(date +%s) > DEADLINE )); then
    echo "FAIL rbac-wait (nach 10 Minuten immer noch 403)"
    exit 1
  fi
  echo "... 403, Rollenzuweisung wirkt noch nicht, warte 30s"
  sleep 30
done

# 1 list
[[ "$STATUS" == "200" ]] && body | jq -e 'length >= 5 and all(.[]; has("id") and (has("PartitionKey") | not))' >/dev/null
check list $? "status=$STATUS body=$(body | head -c 300)"

# 2 list-top
req GET "$BASE?\$top=1" "" 1
[[ "$STATUS" == "200" ]] && body | jq -e 'length >= 5' >/dev/null
check list-top $? "status=$STATUS"

# 3 get-seed
req GET "$BASE/c001" "" 1
[[ "$STATUS" == "200" ]] && body | jq -e '.id == "c001"' >/dev/null
check get-seed $? "status=$STATUS body=$(body | head -c 300)"

# 4 get-no-city
req GET "$BASE/c005" "" 1
[[ "$STATUS" == "200" ]] && body | jq -e 'has("city") | not' >/dev/null
check get-no-city $? "status=$STATUS body=$(body | head -c 300)"

# 5 create
req POST "$BASE" '{"name":"Smoke Test","email":"smoke@example.com","city":"Teststadt"}' 1
NEW_ID=""
if [[ "$STATUS" == "201" ]]; then NEW_ID="$(body | jq -r '.id // empty')"; fi
[[ -n "$NEW_ID" && -n "$(header Location)" ]]
check create $? "status=$STATUS body=$(body | head -c 300)"

if [[ -n "$NEW_ID" ]]; then
  # 6 get-new
  req GET "$BASE/$NEW_ID" "" 1
  [[ "$STATUS" == "200" ]]
  check get-new $? "status=$STATUS"
  # 7 replace
  req PUT "$BASE/$NEW_ID" '{"name":"Smoke Test","email":"smoke@example.com","city":"Neustadt"}' 1
  [[ "$STATUS" == "200" ]] && body | jq -e '.city == "Neustadt"' >/dev/null
  check replace $? "status=$STATUS body=$(body | head -c 300)"
  # 8 get-replaced
  req GET "$BASE/$NEW_ID" "" 1
  [[ "$STATUS" == "200" ]] && body | jq -e '.city == "Neustadt"' >/dev/null
  check get-replaced $? "status=$STATUS"
  # 9 delete
  req DELETE "$BASE/$NEW_ID" "" 1
  [[ "$STATUS" == "204" ]]
  check delete $? "status=$STATUS"
  # 10 get-deleted
  req GET "$BASE/$NEW_ID" "" 1
  [[ "$STATUS" == "404" ]]
  check get-deleted $? "status=$STATUS"
else
  for t in get-new replace get-replaced delete get-deleted; do skip "$t"; done
fi

# 11 put-unknown (und es wurde nichts angelegt)
req PUT "$BASE/does-not-exist" '{"name":"Nobody","email":"nobody@example.com"}' 1
S1="$STATUS"
req GET "$BASE/does-not-exist" "" 1
[[ "$S1" == "404" && "$STATUS" == "404" ]]
check put-unknown $? "put=$S1 get=$STATUS"

# 12 delete-unknown
req DELETE "$BASE/does-not-exist" "" 1
[[ "$STATUS" == "404" ]]
check delete-unknown $? "status=$STATUS"

# 13 create-extra-field
req POST "$BASE" '{"name":"X","email":"x@example.com","PartitionKey":"hack"}' 1
[[ "$STATUS" == "400" ]]
check create-extra-field $? "status=$STATUS"

# 14 create-missing-name
req POST "$BASE" '{"email":"x@example.com"}' 1
[[ "$STATUS" == "400" ]]
check create-missing-name $? "status=$STATUS"

# 15 create-bad-email
req POST "$BASE" '{"name":"X","email":"kein-email"}' 1
[[ "$STATUS" == "400" ]]
check create-bad-email $? "status=$STATUS"

# 16 create-too-large
BIG="$(printf 'a%.0s' $(seq 1 5000))"
req POST "$BASE" "{\"name\":\"$BIG\",\"email\":\"x@example.com\"}" 1
[[ "$STATUS" == "400" || "$STATUS" == "413" ]]
check create-too-large $? "status=$STATUS"

# 17 get-bad-id (a'b)
req GET "$BASE/a%27b" "" 1
[[ "$STATUS" == "400" ]]
check get-bad-id $? "status=$STATUS"

# 18 get-long-id (65 Zeichen)
LONG="$(printf 'a%.0s' $(seq 1 65))"
req GET "$BASE/$LONG" "" 1
[[ "$STATUS" == "400" ]]
check get-long-id $? "status=$STATUS"

# 19 cors-preflight
req OPTIONS "$BASE" "" 0 -H "Origin: $PORTAL_ORIGIN" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: cache-control,content-type,ocp-apim-subscription-key,ocp-apim-trace"
[[ "$(header Access-Control-Allow-Origin)" == "$PORTAL_ORIGIN" ]]
check cors-preflight $? "status=$STATUS allow-origin='$(header Access-Control-Allow-Origin)' erwartet '$PORTAL_ORIGIN'"

# 20 no-key
req GET "$BASE" "" 0
[[ "$STATUS" == "401" ]]
check no-key $? "status=$STATUS"

echo
if (( FAILS == 0 )); then
  echo "Alle Prüfungen bestanden."
  exit 0
fi
echo "${FAILS} Prüfung(en) fehlgeschlagen."
exit 1
