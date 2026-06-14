require 'rails_helper'

RSpec.describe RateCache do
  subject(:cache) { described_class.new }

  let(:rates) { { 'Summer|FloatingPointResort|SingletonRoom' => '27600' } }

  before do
    Rails.cache.clear
    described_class.store_snapshot(nil) # reset the process-global L1 between examples
  end

  describe '#write and #read' do
    it 'writes the batch and reads it back as a CacheEntry' do
      cache.write(rates)
      entry = cache.read

      expect(entry).to be_a(CacheEntry)
      expect(entry.rates).to eq(rates)
      expect(entry).to be_fresh
    end

    it 'returns nil on a miss' do
      expect(cache.read).to be_nil
    end

    it 'stamps fetched_at at write time' do
      travel_to(Time.utc(2026, 6, 14, 12, 0, 0)) do
        entry = cache.write(rates)
        expect(entry.fetched_at).to eq(Time.current.to_i)
      end
    end
  end

  describe 'L1 snapshot' do
    it 'is nil before any read or write' do
      expect(cache.snapshot).to be_nil
    end

    it 'is refreshed on write' do
      cache.write(rates)
      expect(cache.snapshot&.rates).to eq(rates)
    end

    it 'is refreshed on read' do
      cache.write(rates)
      described_class.store_snapshot(nil) # clear, leaving the entry in Redis
      cache.read
      expect(cache.snapshot&.rates).to eq(rates)
    end

    it 'survives a Redis outage and still returns the last-known-good' do
      cache.write(rates) # populates the snapshot
      allow(Rails.cache).to receive(:read).and_raise(Redis::BaseConnectionError)

      expect { cache.read }.to raise_error(described_class::UnavailableError)
      expect(cache.snapshot&.rates).to eq(rates) # snapshot read never touches Redis
    end
  end

  describe 'Redis unavailable' do
    it 'raises UnavailableError when a read hits a connection error' do
      allow(Rails.cache).to receive(:read).and_raise(Redis::BaseConnectionError)
      expect { cache.read }.to raise_error(described_class::UnavailableError)
    end

    it 'raises UnavailableError when a write hits a connection error' do
      allow(Rails.cache).to receive(:write).and_raise(Redis::BaseConnectionError)
      expect { cache.write(rates) }.to raise_error(described_class::UnavailableError)
    end
  end

  describe '#with_refresh_lock' do
    # Keep the waiter loop fast for the threaded examples.
    before do
      allow(PricingConfig).to receive(:waiter_poll_interval).and_return(0.02)
      allow(PricingConfig).to receive(:waiter_cap).and_return(0.5)
    end

    it 'collapses concurrent refreshes to a single winner' do
      mutex = Mutex.new
      block_runs = 0

      results = 10.times.map do
        Thread.new do
          cache.with_refresh_lock do
            mutex.synchronize { block_runs += 1 }
            sleep 0.1            # hold the lock so the others contend, then publish
            cache.write(rates)
          end
        end
      end.map(&:value)

      expect(block_runs).to eq(1) # exactly one winner ran the refresh block
      expect(results).to all(be_a(CacheEntry)) # winner + waiters all received the entry
      expect(results.map(&:rates)).to all(eq(rates))
    end

    it 'returns nil to waiters when the winner does not refresh' do
      held = Queue.new
      winner = Thread.new do
        cache.with_refresh_lock do
          held << true # signal the lock is held
          sleep 0.05
          nil          # winner could not refresh: no write
        end
      end

      held.pop # start the waiter only once the winner holds the lock
      waiter_result = cache.with_refresh_lock { raise 'waiter must not run the block' }
      winner.join

      expect(waiter_result).to be_nil
    end
  end
end
