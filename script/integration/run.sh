#!/usr/bin/env bash
#
# End-to-end integration tests against the docker-compose stack (app + redis +
# rate-api). Brings the stack up with a short freshness window so the stale and
# degradation paths are observable, exercises every documented behaviour, and
# prints a pass/fail summary (non-zero exit on any failure).
#
# Usage:
#   script/integration/run.sh
#
# Env:
#   FRESH=<seconds>   freshness window for the run (default 3)
#   KEEP_UP=1         leave the stack running afterwards (default: docker compose down)
#   BASE_URL=...      override the app URL (default http://localhost:3000)

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
source script/integration/lib.sh

FRESH="${FRESH:-3}"
PARAMS="period=Summer&hotel=FloatingPointResort&room=SingletonRoom"
PRICING="/api/v1/pricing?${PARAMS}"

echo "Bringing up the stack (PRICING_FRESH_WINDOW_SECONDS=${FRESH})..."
PRICING_FRESH_WINDOW_SECONDS="$FRESH" $COMPOSE up -d --build >/dev/null 2>&1
restart_svc rate-api # reset the daily quota
wait_for_app || exit 1

section "1. Happy path (cold miss -> upstream refresh)"
redis_flush
http_get "$PRICING"
assert_eq "$HTTP_CODE" "200" "200 OK"
assert_eq "$(header_value X-Cache-Status)" "miss" "X-Cache-Status: miss"
assert_match "$(json_field rate)" '^[0-9]+$' "rate is a digit string"
assert_eq "$(json_field stale)" "false" "stale: false"
assert_match "$(header_value Age)" '^[0-9]+$' "Age header present"

section "2. Warm hit (served from cache)"
http_get "$PRICING"
assert_eq "$HTTP_CODE" "200" "200 OK"
assert_eq "$(header_value X-Cache-Status)" "hit" "X-Cache-Status: hit"

section "3. Batching (one upstream call serves every combo)"
http_get "/api/v1/pricing?period=Autumn&hotel=GitawayHotel&room=RestfulKing"
assert_eq "$HTTP_CODE" "200" "a different combo is also served"
http_get "/internal/stats"
assert_eq "$(json_field calls_today)" "1" "calls_today == 1 (single batch)"

section "4. /internal/stats"
http_get "/internal/stats"
assert_eq "$(json_field redis)" "up" "redis: up"
assert_eq "$(json_field cache_status)" "fresh" "cache_status: fresh"

section "5. Input validation"
http_get "/api/v1/pricing?period=Nope&hotel=GitawayHotel&room=RestfulKing"
assert_eq "$HTTP_CODE" "400" "invalid period -> 400"
assert_match "$HTTP_BODY" "Invalid period" "error names the invalid field"
http_get "/api/v1/pricing"
assert_eq "$HTTP_CODE" "400" "missing params -> 400"
assert_match "$HTTP_BODY" "Missing required" "error names the missing params"

section "6. Upstream down + stale cache -> serve stale (200)"
http_get "$PRICING" # ensure the cache is warm
stop_svc rate-api
sleep "$((FRESH + 1))" # let the entry age past the freshness window
http_get "$PRICING"
assert_eq "$HTTP_CODE" "200" "200 OK (degraded)"
assert_eq "$(json_field stale)" "true" "stale: true"
assert_eq "$(header_value X-Cache-Status)" "stale" "X-Cache-Status: stale"

section "7. Upstream down + cold cache -> 503"
redis_flush
http_get "$PRICING"
assert_eq "$HTTP_CODE" "503" "503 Service Unavailable"
assert_match "$HTTP_BODY" "unavailable" "descriptive error"
start_svc rate-api
wait_for_app

section "8. Redis down -> serve L1 snapshot as stale"
http_get "$PRICING" # warm the cache (and the in-process snapshot)
stop_svc redis
http_get "$PRICING"
assert_eq "$HTTP_CODE" "200" "200 OK (from snapshot)"
assert_eq "$(json_field stale)" "true" "stale: true"
assert_eq "$(header_value X-Cache-Status)" "stale" "X-Cache-Status: stale"
http_get "/internal/stats"
assert_eq "$(json_field redis)" "down" "stats report redis: down"
start_svc redis
wait_for_app

section "9. Redis down + no snapshot -> 503"
redis_flush                  # cold redis
restart_svc interview-dev    # fresh process => empty in-process snapshot
wait_for_app
stop_svc redis
http_get "$PRICING"
assert_eq "$HTTP_CODE" "503" "503 (Redis down, no snapshot)"
start_svc redis
wait_for_app

if [ "${KEEP_UP:-}" = "1" ]; then
  echo; echo "Leaving the stack up (KEEP_UP=1)."
else
  echo; echo "Tearing down (set KEEP_UP=1 to keep the stack)..."
  $COMPOSE down >/dev/null 2>&1
fi

summary
