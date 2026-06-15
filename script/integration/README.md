# Integration tests

Black-box, end-to-end checks that drive the running service over HTTP against the
real `docker-compose` stack (app + Redis + the `tripladev/rate-api` upstream).
They complement the RSpec suite (which uses an in-memory cache + WebMock) by
exercising the genuine Redis, the real upstream, and the failure paths against
live containers.

## Run

```bash
script/integration/run.sh
```

This brings the stack up (with a short freshness window so the stale paths are
observable), runs every case, prints a pass/fail summary, and tears the stack
down. Exit code is non-zero if any assertion fails.

Options (env vars):

- `FRESH=<seconds>` — freshness window for the run (default `3`).
- `KEEP_UP=1` — leave the stack running afterwards.
- `BASE_URL=...` — point at a different host (default `http://localhost:3000`).

## Cases covered

1. Happy path: cold miss → upstream refresh (200, `X-Cache-Status: miss`, digit-string rate, `Age`).
2. Warm hit served from cache (`X-Cache-Status: hit`).
3. Batching: a second combo is served from the same batch (`calls_today == 1`).
4. `/internal/stats` reports live Redis state.
5. Input validation (400 for invalid/missing params).
6. Upstream down + stale cache → serve stale (200, `stale: true`).
7. Upstream down + cold cache → 503.
8. Redis down → serve the per-process L1 snapshot as stale.
9. Redis down + no snapshot → 503.

## Notes

- `run.sh` stops/starts the `redis` and `rate-api` containers to simulate
  outages, and restarts `interview-dev` to clear the in-process snapshot for
  case 9, restoring everything as it goes.
- The freshness-window override rides on the `PRICING_FRESH_WINDOW_SECONDS`
  passthrough in `docker-compose.yml`; it is empty (code default) for normal runs.
