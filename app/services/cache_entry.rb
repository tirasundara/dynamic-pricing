# Immutable snapshot of the cached rate batch plus its freshness policy.
#
# `rates` is a combo => rate map ({ "period|hotel|room" => "<digits>" }), the
# validated form BatchValidator produces, not the upstream's `rates` array.
# `fetched_at` is an epoch integer. The freshness thresholds are injected (from
# PricingConfig via RateCache) so the entry self-classifies yet stays configurable.
CacheEntry = Data.define(:rates, :fetched_at, :fresh_window, :max_stale) do
  # Seconds since the batch was fetched. Uses Time.current so it tracks the clock
  # (and travel_to in specs); no injected clock needed.
  def age = Time.current.to_i - fetched_at

  # :fresh   while age < fresh_window           (servable as a normal hit)
  # :stale   while fresh_window <= age < max_stale (degradation path only)
  # :expired once age >= max_stale              (treat as missing)
  def status
    seconds = age
    return :fresh if seconds < fresh_window
    return :stale if seconds < max_stale

    :expired
  end

  def fresh?   = status == :fresh
  def stale?   = status == :stale
  def expired? = status == :expired
end
