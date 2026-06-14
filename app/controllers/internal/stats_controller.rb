# Diagnostic snapshot of live state: the daily upstream budget and the cached
# batch's freshness. Degrades gracefully when Redis is down (reports it and falls
# back to the L1 snapshot) rather than erroring.
class Internal::StatsController < ApplicationController
  def show
    render json: stats
  end

  private

  def stats
    cache = RateCache.new
    budget = BudgetGate.new
    entry = cache.read

    {
      redis: "up",
      calls_today: budget.count,
      calls_remaining: budget.remaining,
      cache_status: entry ? entry.status : "missing",
      cache_age_seconds: entry&.age
    }
  rescue RedisBacked::UnavailableError
    snapshot = cache.snapshot
    {
      redis: "down",
      calls_today: nil,
      calls_remaining: nil,
      cache_status: snapshot ? "snapshot" : "missing",
      cache_age_seconds: snapshot&.age
    }
  end
end
