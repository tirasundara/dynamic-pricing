# Dynamic Pricing Proxy

A Rails service that fronts Tripla's expensive, rate-limited dynamic pricing model and serves room rates to users cheaply and reliably.

The model API allows only **1,000 calls per day on a single token**, yet the service must answer **at least 10,000 user requests per day** with rates **no older than 5 minutes**, and stay up when the model is slow, failing, or rate-limited.

> **Start with [`docs/design.md`](docs/design.md).** It's the design document I wrote for this service: the constraint analysis, the options I weighed, the trade-offs, the failure-mode matrix, and the upstream behavior I verified by hand. It is the best place to understand why the service is built the way it is. This README covers how to run, test, and use it.

## How it works

A naive proxy calls the model once per request, roughly 10x over budget. This service decouples user load from upstream load:

- **Batch.** One upstream call fetches all 36 combinations (4 periods x 3 hotels x 3 rooms), so a refresh costs one call, not 36.
- **Cache in Redis.** The whole batch lives under one key; reads classify it by age, serving anything under 5 minutes directly and refreshing older entries.
- **Single-flight.** When the entry needs refreshing, one request wins a Redis lock and calls upstream while everyone else waits for its result. A stampede collapses into one call.
- **Budget gate.** A per-day counter caps upstream calls as a backstop against bugs.
- **Degrade, don't fail.** If upstream is down or returns junk, the service serves the last good rate flagged stale. If Redis is down, it serves a per-process snapshot. Only with nothing usable does it return a 503.

Worst case is about 288 upstream calls/day (one refresh per 5-minute window), well under the 1,000 cap.

## Running it

The stack runs in Docker: the app, Redis, and the `tripladev/rate-api` model API.

```bash
docker compose up -d --build

curl 'http://localhost:3000/api/v1/pricing?period=Summer&hotel=FloatingPointResort&room=SingletonRoom'
# {"rate":"25700","stale":false,"as_of":"2026-06-14T07:33:18Z"}

curl 'http://localhost:3000/internal/stats'
# {"redis":"up","calls_today":1,"calls_remaining":999,"cache_status":"fresh","cache_age_seconds":0}
```

## Testing

RSpec for unit and request specs, plus a black-box integration suite that drives the real containers.

```bash
# RSpec (in-memory cache + stubbed HTTP; needs no Redis or upstream)
docker compose run --rm --no-deps -e RAILS_ENV=test interview-dev bundle exec rspec

# Integration (brings the stack up, exercises every path incl. upstream-down and Redis-down)
script/integration/run.sh
```

The integration cases are listed in [`script/integration/README.md`](script/integration/README.md).

## API

### `GET /api/v1/pricing`

All three query parameters are required:

| Param | Valid values |
| --- | --- |
| `period` | `Summer`, `Autumn`, `Winter`, `Spring` |
| `hotel` | `FloatingPointResort`, `GitawayHotel`, `RecursionRetreat` |
| `room` | `SingletonRoom`, `BooleanTwin`, `RestfulKing` |

Success (`200`) returns the same body whether fresh or stale, plus `Age` (seconds since fetch) and `X-Cache-Status` (`hit` / `miss` / `stale`) headers:

```json
{ "rate": "25700", "stale": false, "as_of": "2026-06-14T07:33:18Z" }
```

`rate` is always a digit string (rationale in the design doc). Errors share the shape `{ "error": "..." }`: `400` for a missing or unrecognized parameter (with the supported values), and `503` when upstream and the cache are both unusable.

### `GET /internal/stats`

A diagnostic endpoint reporting the daily call counters and the cache's freshness. It degrades to a `redis: "down"` report instead of erroring when Redis is unavailable. No auth; it would be network-restricted in production.

## Configuration

Every knob is an environment variable with a sane default.

| Variable | Default | Purpose |
| --- | --- | --- |
| `RATE_API_URL` | `http://localhost:8080` | Upstream model API base URL |
| `RATE_API_TOKEN` | (provided token) | Upstream auth token |
| `REDIS_URL` | `redis://localhost:6379/0` | Shared cache / lock / budget store |
| `PRICING_FRESH_WINDOW_SECONDS` | `300` | Freshness ceiling (the 5-minute rule) |
| `PRICING_MAX_STALE_SECONDS` | `3600` | How long stale is servable; also the cache TTL |
| `PRICING_LOCK_TTL_SECONDS` | `10` | Single-flight lock lifetime |
| `PRICING_WAITER_CAP_SECONDS` | `8` | How long a waiter polls before degrading |
| `PRICING_WAITER_POLL_INTERVAL_SECONDS` | `0.1` | Waiter poll cadence |
| `PRICING_OPEN_TIMEOUT_SECONDS` | `2` | Upstream connect timeout |
| `PRICING_READ_TIMEOUT_SECONDS` | `3` | Upstream read timeout |
| `PRICING_DAILY_QUOTA` | `1000` | Upstream daily cap (drives `calls_remaining`) |
| `PRICING_BUDGET_WARN` | `800` | Warn threshold on the daily counter |
| `PRICING_BUDGET_LIMIT` | `950` | Hard gate: skip upstream and degrade past this |

## Observability

Each decision point emits an `ActiveSupport::Notifications` event, and one subscriber renders each as a single line of JSON via `Rails.logger`, correlated by `request_id`:

```json
{"event":"cache_missed","timestamp":"2026-06-14T07:33:18.564Z","duration_ms":0.01,"request_id":"328c...","period":"Summer","hotel":"FloatingPointResort","room":"SingletonRoom"}
{"event":"upstream_call","timestamp":"2026-06-14T07:33:18.577Z","duration_ms":19.18,"request_id":"328c...","period":"Summer","hotel":"FloatingPointResort","room":"SingletonRoom"}
```

That subscriber is the seam: to ship real metrics, swap `Rails.logger` for a StatsD or Prometheus emitter in one place, leaving the business code untouched.

## Design

[`docs/design.md`](docs/design.md) is the primary design document. It covers:

- the constraint math (why batching is mandatory, not optional);
- the four approaches I considered, their trade-offs, and why single-flight won;
- the failure-mode matrix and the degradation path;
- the single-flight, budget-metering, and L1-snapshot mechanics with their invariants;
- the upstream behavior verified against the live image;
- the alternatives I rejected (stale-while-revalidate, lenient batch validation, Prometheus/Grafana, raw `redis-rb`).

A few assumptions worth surfacing here:

- "No older than 5 minutes" is a hard ceiling on the normal path; staleness happens only on the documented degradation path.
- During an outage, a slightly stale rate beats an error for browsing. How long stale is acceptable is a business call, so it is configurable.
- The budget counter resets at midnight UTC; the upstream's real reset timezone is unconfirmed, so the gate sits below the cap.
- The upstream returns `rate` as a JSON number; the proxy normalizes it to a string so clients get one stable, precision-safe type.

Invalid parameters return `400`, not `422`. Both are defensible for enum validation, so I kept the scaffold's established `400` contract rather than churn it.

## Project layout

```
app/models/
  combos.rb            # the 36-combo attribute space + the shared cache key
  cache_entry.rb       # cached batch as a value object; classifies itself by age
  outcome.rb           # the value object the service returns to the controller
app/services/
  rate_cache.rb        # Redis read/write, L1 snapshot, single-flight lock
  batch_validator.rb   # all-or-nothing validation of an upstream response
  budget_gate.rb       # daily upstream-call counter and gate
  redis_backed.rb      # shared Redis failure handling (UnavailableError)
  pricing_config.rb    # every tunable, read from ENV
  api/v1/pricing_service.rb        # the orchestrator
lib/rate_api_client.rb             # upstream HTTP client (transport only)
app/controllers/api/v1/pricing_controller.rb
app/controllers/internal/stats_controller.rb
config/initializers/pricing_instrumentation.rb   # the JSON log subscriber
docs/design.md                     # the design document
script/integration/                # black-box integration tests
```

## AI usage

The FAQ asks how I used AI on this assignment. I used **Claude Code** (Anthropic's CLI) as a pair-programming and design partner, in three parts.

**1. Design and stress-testing.** The design is mine. I drafted the first version of [`docs/design.md`](docs/design.md) by hand: the constraint math and the core approach (fetch on demand, batch all 36 combinations, cache in Redis, single-flight locking, graceful degradation). Then I used Claude to stress-test it, debating the trade-offs one decision at a time. A few of my original calls changed when the counter-argument was better; most held. The final call on each was mine.

**2. Profiling the upstream (human-led).** Rather than trust the provided docs, I ran the real `tripladev/rate-api` container and profiled what it actually does. That surfaced undocumented behavior that shaped the error handling:

- the rate limit returns `429 Too Many Requests`;
- the API fails on roughly 14% of calls;
- the failures aren't clean: some are 500s, others a `200 OK` with a `{"status":"error"}` body pretending to be fine;
- `rate` comes back as a JSON number, not the string the docs show.

**3. Implementation.** I used Claude to accelerate the build, one component at a time, but I reviewed every file and test before committing. I steered the decisions that mattered: serving the rate as a string, the owner-checked lock release, the upstream error taxonomy, and trimming over-abstraction to keep the code idiomatic Ruby. I pushed back when I disagreed, and wrote every commit message myself.

The design, the trade-offs, and the code are mine. I can walk through any line and explain why it is there.
