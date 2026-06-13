# Central source of every runtime tunable for the pricing proxy.
#
# One reader per knob, each pulling from ENV with a sane default, so all tunables
# live in one auditable place and can be overridden per environment (12-factor)
# without code changes. Values are read on each call (not memoized) so specs can
# stub ENV and assert overrides; the cost is a negligible ENV lookup.
#
# Connection coordinates and the upstream token deliberately live on RateApiClient,
# not here: this module holds behavioral tunables, not the external adapter's
# address or credentials.
#
# Timing invariant (asserted in the spec):
#   open_timeout + read_timeout < waiter_cap < lock_ttl
# so the upstream call finishes inside the lock, and a waiter polls long enough to
# catch the winner's write yet degrades before the lock's hard expiry.
module PricingConfig
  module_function

  # Freshness ceiling: an entry is "fresh" while age < fresh_window (the 5-minute rule).
  def fresh_window = env_int('PRICING_FRESH_WINDOW_SECONDS', 300)

  # Max staleness servable on the degradation path; also the cache key TTL.
  def max_stale = env_int('PRICING_MAX_STALE_SECONDS', 3600)

  # Single-flight lock lifetime; self-releases so a crashed winner cannot wedge the key.
  def lock_ttl = env_int('PRICING_LOCK_TTL_SECONDS', 10)

  # How long a waiter polls for the winner's refresh before degrading.
  def waiter_cap = env_int('PRICING_WAITER_CAP_SECONDS', 8)

  # Waiter poll cadence while waiting on the winner.
  def waiter_poll_interval = env_float('PRICING_WAITER_POLL_INTERVAL_SECONDS', 0.1)

  # Upstream HTTP connect timeout.
  def open_timeout = env_int('PRICING_OPEN_TIMEOUT_SECONDS', 2)

  # Upstream HTTP read timeout (bounds the in-lock wait).
  def read_timeout = env_int('PRICING_READ_TIMEOUT_SECONDS', 3)

  # Upstream daily quota (the cap we must stay under); drives calls_remaining.
  def daily_quota = env_int('PRICING_DAILY_QUOTA', 1000)

  # Warn threshold on the daily attempt counter.
  def budget_warn = env_int('PRICING_BUDGET_WARN', 800)

  # Hard gate: at/after this many attempts today, skip upstream and degrade.
  def budget_limit = env_int('PRICING_BUDGET_LIMIT', 950)

  def env_int(key, default) = ENV[key].present? ? Integer(ENV[key], 10) : default

  def env_float(key, default) = ENV[key].present? ? Float(ENV[key]) : default
end
