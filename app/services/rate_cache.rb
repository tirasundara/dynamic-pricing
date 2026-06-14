require "securerandom"

# Owns the Redis rate keyspace and coordinates its refresh: read/write the batch,
# the process-global L1 snapshot, and the single-flight lock. Translates Redis
# connection errors into RateCache::UnavailableError so the service can fall back to
# the snapshot and never call upstream without Redis.
class RateCache
  class UnavailableError < StandardError; end

  RATES_KEY = "pricing:rates:v1".freeze
  LOCK_KEY  = "pricing:rates:lock".freeze

  class << self
    # Process-global last-known-good snapshot (L1): a frozen CacheEntry or nil.
    # Replaced by whole-reference assignment (atomic in MRI), so no mutex.
    attr_reader :snapshot

    def store_snapshot(entry)
      @snapshot = entry
    end
  end

  # Reads the cached batch as a CacheEntry, or nil on a miss. Refreshes the L1
  # snapshot on a hit. Raises UnavailableError if Redis is unreachable.
  def read
    raw = with_redis { Rails.cache.read(RATES_KEY) }
    return nil if raw.nil?

    # Store the entry in the L1 snapshot cache (the process-global last-known-good snapshot).
    remember(build_entry(raw[:rates], raw[:fetched_at]))
  end

  # Writes the batch with fetched_at = now and TTL = max_stale, refreshes the L1
  # snapshot, and returns the written CacheEntry. Raises UnavailableError on a Redis error.
  def write(rates)
    fetched_at = Time.current.to_i
    with_redis do
      Rails.cache.write(RATES_KEY, { rates: rates, fetched_at: fetched_at }, expires_in: PricingConfig.max_stale)
    end
    remember(build_entry(rates, fetched_at))
  end

  # The process-global L1 snapshot, or nil. Pure in-process: never touches Redis,
  # so it never raises, which is what makes it servable while Redis is down.
  def snapshot
    self.class.snapshot
  end

  # Single-flight refresh. The first caller to acquire the lock is the winner: it
  # yields (the block refreshes and returns the fresh CacheEntry, or nil if it
  # could not) and releases the lock afterward. Everyone else waits, polling the
  # cache up to waiter_cap, and returns the refreshed entry or nil on timeout.
  # Block exceptions propagate; the lock is released either way.
  def with_refresh_lock
    token = SecureRandom.hex(16)
    if acquire_lock(token)
      begin
        yield
      ensure
        release_lock(token)
      end
    else
      wait_for_refresh
    end
  end

  private

  def remember(entry)
    self.class.store_snapshot(entry)
    entry
  end

  def build_entry(rates, fetched_at)
    CacheEntry.new(
      rates: rates,
      fetched_at: fetched_at,
      fresh_window: PricingConfig.fresh_window,
      max_stale: PricingConfig.max_stale
    ).freeze
  end

  def acquire_lock(token)
    with_redis do
      Rails.cache.write(LOCK_KEY, token, unless_exist: true, expires_in: PricingConfig.lock_ttl)
    end
  end

  # Best-effort owner-checked release: delete the lock only if it still carries
  # our token, so we never release a newer winner's lock. The TTL is the safety
  # net if this is skipped (e.g. our process died). Never raises out.
  def release_lock(token)
    with_redis do
      Rails.cache.delete(LOCK_KEY) if Rails.cache.read(LOCK_KEY) == token
    end
  rescue UnavailableError
    nil
  end

  def wait_for_refresh
    deadline = monotonic + PricingConfig.waiter_cap
    loop do
      entry = read
      return entry if entry&.fresh?
      return nil if monotonic >= deadline

      sleep(PricingConfig.waiter_poll_interval)
    end
  end

  def with_redis
    yield
  rescue Redis::BaseConnectionError => e
    raise UnavailableError, e.message
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
