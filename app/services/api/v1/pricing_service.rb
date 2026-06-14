module Api::V1
  # Orchestrates a single rate lookup. Sets `result` (an Outcome) for a servable
  # 200 response, or pushes a reason to `errors` for a 503. Collaborators are
  # injected with sensible defaults for testability.
  class PricingService < BaseService
    def initialize(period:, hotel:, room:, cache: RateCache.new, client: RateApiClient, budget: BudgetGate.new)
      @period = period
      @hotel = hotel
      @room = room
      @cache = cache
      @client = client
      @budget = budget
    end

    # Classify the cached batch by age:
    #   fresh      -> serve hit
    #   stale/miss -> single-flight refresh; serve it, or degrade
    #   Redis down -> serve the in-process L1 snapshot, never calling upstream
    def run
      entry = @cache.read
      return hit(entry) if entry&.fresh?

      refreshed = @cache.with_refresh_lock { refresh }
      return serve(refreshed, :miss) if refreshed

      degrade
    rescue RedisBacked::UnavailableError
      serve_snapshot
    end

    private

    # Winner-only refresh: reserve budget, fetch all combos, validate, write.
    # Returns the fresh CacheEntry, or nil if it could not refresh (budget gated,
    # upstream failure, or an invalid batch) so the caller degrades.
    def refresh
      return nil unless @budget.reserve

      body = @client.fetch_all!(attributes: Combos.all)
      result = BatchValidator.call(body, expected: Combos.all)
      return nil unless result.valid?

      @cache.write(result.rates)
    rescue RateApiClient::UpstreamError
      nil
    end

    # Re-read once (a concurrent winner may have just refreshed) and classify.
    def degrade
      entry = @cache.read
      case entry&.status
      when :fresh then hit(entry)
      when :stale then serve(entry, :stale)
      else unavailable!
      end
    end

    # Redis is unreachable: serve the process-local last-known-good snapshot,
    # always flagged stale (the age classifier only decides servability), and
    # never call upstream.
    def serve_snapshot
      entry = @cache.snapshot
      return unavailable! if entry.nil? || entry.expired?

      serve(entry, :stale)
    end

    def hit(entry) = serve(entry, :hit)

    def serve(entry, cache_status)
      rate = entry.rates[key]
      return unavailable! if rate.nil?

      @result = Outcome.new(rate: rate, fetched_at: entry.fetched_at, cache_status: cache_status)
    end

    def unavailable!
      errors << "Service temporarily unavailable: no recent rate for the requested room."
      nil
    end

    def key
      @key ||= Combos.key(@period, @hotel, @room)
    end
  end
end
