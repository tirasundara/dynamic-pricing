# Daily upstream-call budget, backed by a date-keyed Redis counter.
#
# The gate is a backstop against runaway refreshes (a lock regression, a crash
# loop), not the normal control path: legitimate worst-case usage is ~288/day
# against a 1,000/day cap. Redis connection errors surface as
# RedisBacked::UnavailableError, the app-wide "Redis unavailable" signal.
class BudgetGate
  include RedisBacked

  COUNTER_TTL = 48.hours

  # Reserves one upstream attempt if under the daily limit. Returns true (the
  # caller may call upstream; the attempt is now counted) or false (limit reached;
  # the caller must skip upstream and degrade). The increment happens before the
  # upstream call, so it counts attempts including ones that later time out, never
  # under-counting vs the upstream's own metering. Called only by the winner under
  # the single-flight lock, so the read-then-increment is serialized.
  def reserve
    return false if count >= PricingConfig.budget_limit

    with_redis { Rails.cache.increment(key, 1, expires_in: COUNTER_TTL) }
    true
  end

  # Upstream attempts counted today.
  def count
    with_redis { Rails.cache.read(key, raw: true).to_i }
  end

  # Attempts left before the daily quota (clamped at zero).
  def remaining
    [PricingConfig.daily_quota - count, 0].max
  end

  # Whether usage has crossed the warning threshold.
  def warn?
    count >= PricingConfig.budget_warn
  end

  private

  # Date-keyed so the counter resets at midnight UTC; UTC explicitly, independent
  # of the app's configured time zone.
  def key
    "pricing:budget:#{Time.now.utc.strftime('%Y-%m-%d')}"
  end
end
