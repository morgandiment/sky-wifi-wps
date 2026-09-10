#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "[-] Error: .env file not found at $ENV_FILE"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

ROUTER_HOST=$(echo "${SKY_ROUTER_HOST:-myrouter.io}" | tr -d '\r"' | xargs)
ROUTER_IP=$(echo "${SKY_ROUTER_IP:-192.168.0.1}" | tr -d '\r"' | xargs)
USERNAME=$(echo "${SKY_USERNAME:-admin}" | tr -d '\r"' | xargs)
PASSWORD=$(echo "$SKY_PASSWORD" | tr -d '\r"' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

if [ -z "$PASSWORD" ]; then
  echo "[-] Error: SKY_PASSWORD is empty."
  exit 1
fi

ROUTER="https://${ROUTER_HOST}"
RESOLVE_FLAG="--resolve ${ROUTER_HOST}:443:${ROUTER_IP}"

COOKIE_FILE=$(mktemp /tmp/sky_wps.XXXXXX)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "[*] Target: ${ROUTER} via IP ${ROUTER_IP}"
echo "[*] Initializing pre-auth session..."

# 1. Initialize session
curl -k -s --connect-timeout 5 $RESOLVE_FLAG -c "$COOKIE_FILE" "$ROUTER/index.jst" > /dev/null

echo "[*] Authenticating..."

# 2. Authenticate
LOGIN_RESP=$(curl -k -s --connect-timeout 5 $RESOLVE_FLAG -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
  -X POST "$ROUTER/check.jst" \
  -H "Host: ${ROUTER_HOST}" \
  -H "Origin: $ROUTER" \
  -H "Referer: $ROUTER/index.jst" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-raw "username=${USERNAME}&password=${PASSWORD}&locale=en_GB.utf8")

if echo "$LOGIN_RESP" | grep -q "Username or password is incorrect"; then
  echo "[-] Authentication failed: Router rejected username or password."
  exit 1
fi

echo "[*] Loading WPS page to generate token..."

# 3. Request WPS page WITH -c so new Set-Cookie directives are saved
WPS_PAGE=$(curl -k -s --connect-timeout 5 $RESOLVE_FLAG -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
  "$ROUTER/wireless_network_configuration_wps.jst")

# Try 1: Extract from updated cookie file
CSRF_TOKEN=$(grep "csrfp_token" "$COOKIE_FILE" | awk '{print $NF}' | tail -n 1)

# Try 2: Extract from hidden input or meta tag in the HTML body
if [ -z "$CSRF_TOKEN" ]; then
  CSRF_TOKEN=$(echo "$WPS_PAGE" | grep -o 'name="csrfp_token"[^>]*' | grep -o 'value="[^"]*"' | cut -d'"' -f2)
fi

# Try 3: Extract from JS inline variable assignment
if [ -z "$CSRF_TOKEN" ]; then
  CSRF_TOKEN=$(echo "$WPS_PAGE" | grep -o 'csrfp_token[[:space:]]*=[[:space:]]*["'\''][^"'\'']*' | head -n 1 | sed -E 's/.*["'\'']([^"'\'']+)["'\''].*/\1/')
fi

if [ -z "$CSRF_TOKEN" ]; then
  echo "[-] Failed to retrieve CSRF token."
  exit 1
fi

echo "[+] Token acquired: [${CSRF_TOKEN}]"
echo "[*] Triggering WPS PushButton..."

# 4. Fire the trigger
PAYLOAD="configInfo=%7B%22ssid_number%22%3A%221%22%2C+%22target%22%3A%22pair_client%22%2C+%22wps_enabled%22%3A%22true%22%2C+%22wps_method%22%3A%22PushButton%2CPIN%22%2C+%22pair_method%22%3A%22PushButton%22%2C+%22pin_number%22%3A%22%22%7D&csrfp_token=${CSRF_TOKEN}"

RESPONSE=$(curl -k -s --connect-timeout 5 $RESOLVE_FLAG -b "$COOKIE_FILE" \
  -X POST "$ROUTER/actionHandler/ajaxSet_wps_config.jst" \
  -H "Host: ${ROUTER_HOST}" \
  -H "Origin: $ROUTER" \
  -H "Referer: $ROUTER/wireless_network_configuration_wps.jst" \
  -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
  -H "X-Requested-With: XMLHttpRequest" \
  --data-raw "$PAYLOAD")

if echo "$RESPONSE" | grep -q '"pair_method":"PushButton"'; then
  echo "[+] WPS PushButton active! Pair window open for 120 seconds."
else
  echo "[-] Trigger failed. Server returned: $RESPONSE"
  exit 1
fi