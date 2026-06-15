#!/usr/bin/env bash
# Shared helpers for the integration tests (script/integration/run.sh).
# Sourced, not run directly.

set -uo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
COMPOSE="docker compose"

if [ -t 1 ]; then
  GREEN=$'\e[32m'; RED=$'\e[31m'; YELLOW=$'\e[33m'; DIM=$'\e[2m'; RESET=$'\e[0m'
else
  GREEN=; RED=; YELLOW=; DIM=; RESET=
fi

PASS=0
FAIL=0
HDR_FILE=""

# http_get PATH  -> sets HTTP_CODE, HTTP_BODY, and writes response headers to HDR_FILE.
http_get() {
  HDR_FILE="$(mktemp)"
  local out
  out="$(curl -s -D "$HDR_FILE" -w $'\n%{http_code}' "$BASE_URL$1")"
  HTTP_CODE="${out##*$'\n'}"
  HTTP_BODY="${out%$'\n'*}"
}

# header_value NAME  -> value of the (case-insensitive) response header, CR-stripped.
header_value() {
  awk -v h="$1" 'BEGIN{IGNORECASE=1} tolower($0) ~ "^" tolower(h) ":" {
    sub(/^[^:]*:[ ]*/, ""); gsub(/\r/, ""); print; exit
  }' "$HDR_FILE"
}

# json_field KEY  -> value for a flat top-level JSON key (quotes stripped).
json_field() {
  echo "$HTTP_BODY" | grep -oE "\"$1\":(\"[^\"]*\"|[^,}]*)" | head -1 \
    | sed -E "s/\"$1\"://; s/^\"//; s/\"$//"
}

ok()  { PASS=$((PASS + 1)); echo "  ${GREEN}[PASS]${RESET} $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  ${RED}[FAIL]${RESET} $1"; [ -n "${2:-}" ] && echo "         ${DIM}$2${RESET}"; }

assert_eq() { # actual expected message
  if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "expected '$2', got '$1'"; fi
}

assert_match() { # value regex message
  if echo "$1" | grep -qE "$2"; then ok "$3"; else bad "$3" "'$1' does not match /$2/"; fi
}

section() { echo; echo "${YELLOW}== $1 ==${RESET}"; }

wait_for_app() {
  local i
  for i in $(seq 1 40); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/internal/stats" 2>/dev/null)" = "200" ] && return 0
    sleep 1
  done
  echo "${RED}app did not become ready at $BASE_URL${RESET}"
  return 1
}

redis_flush() { $COMPOSE exec -T redis redis-cli FLUSHALL >/dev/null 2>&1; }
stop_svc()    { $COMPOSE stop "$1" >/dev/null 2>&1; }
start_svc()   { $COMPOSE start "$1" >/dev/null 2>&1; }
restart_svc() { $COMPOSE restart "$1" >/dev/null 2>&1; }

summary() {
  echo
  if [ "$FAIL" -eq 0 ]; then
    echo "${YELLOW}== summary ==${RESET}  ${GREEN}${PASS} passed, 0 failed${RESET}"
  else
    echo "${YELLOW}== summary ==${RESET}  ${GREEN}${PASS} passed${RESET}, ${RED}${FAIL} failed${RESET}"
  fi
  [ "$FAIL" -eq 0 ]
}
