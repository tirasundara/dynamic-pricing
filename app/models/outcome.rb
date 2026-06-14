# What PricingService returns for a servable (200) response: the requested
# combo's rate plus the metadata the controller needs for the body and the
# Age / X-Cache-Status headers. Built only for fresh/stale hits; the 503 path
# (no usable rate) uses the service's errors instead.
#
# cache_status is one of :hit (fresh from cache), :miss (just refreshed),
# or :stale (served on the degradation path). stale?, as_of, and age are derived
# so there is a single source of truth.
Outcome = Data.define(:rate, :fetched_at, :cache_status) do
  def stale? = cache_status == :stale

  # ISO8601 UTC of when the rate was fetched, e.g. "2026-06-14T12:00:00Z".
  def as_of = Time.at(fetched_at).utc.iso8601

  # Seconds since the rate was fetched, for the Age header (clamped at 0).
  def age = [Time.current.to_i - fetched_at, 0].max
end
