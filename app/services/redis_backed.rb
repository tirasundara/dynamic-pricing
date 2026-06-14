# Shared Redis failure handling for the Redis-backed collaborators (RateCache,
# BudgetGate). Wrap Redis operations in `with_redis` so a connection error
# surfaces as UnavailableError, the app-wide "Redis is unavailable" signal that
# the service rescues to fall back to the L1 snapshot and never call upstream
# without Redis.
module RedisBacked
  # Raised when a Redis-backed operation cannot reach Redis.
  class UnavailableError < StandardError; end

  private

  def with_redis
    yield
  rescue Redis::BaseConnectionError => e
    raise UnavailableError, e.message
  end
end
