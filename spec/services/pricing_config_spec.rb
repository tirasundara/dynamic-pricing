require 'rails_helper'

RSpec.describe PricingConfig do
  # Set an ENV var for the duration of the block, then restore it, so overrides
  # in one example never leak into another.
  def with_env(key, value)
    original = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = original
  end

  describe 'defaults (no ENV set)' do
    {
      fresh_window: 300,
      max_stale: 3600,
      lock_ttl: 10,
      waiter_cap: 8,
      waiter_poll_interval: 0.1,
      open_timeout: 2,
      read_timeout: 3,
      daily_quota: 1000,
      budget_warn: 800,
      budget_limit: 950
    }.each do |reader, default|
      it "#{reader} defaults to #{default}" do
        expect(described_class.public_send(reader)).to eq(default)
      end
    end
  end

  describe 'ENV overrides' do
    it 'parses an integer reader from ENV' do
      with_env('PRICING_MAX_STALE_SECONDS', '60') do
        expect(described_class.max_stale).to eq(60)
      end
    end

    it 'parses a float reader from ENV' do
      with_env('PRICING_WAITER_POLL_INTERVAL_SECONDS', '0.25') do
        expect(described_class.waiter_poll_interval).to eq(0.25)
      end
    end

    it 'treats a blank ENV value as unset and falls back to the default' do
      with_env('PRICING_LOCK_TTL_SECONDS', '') do
        expect(described_class.lock_ttl).to eq(10)
      end
    end
  end

  describe 'timing invariant' do
    it 'holds for the defaults: open + read < waiter_cap < lock_ttl' do
      upstream_worst_case = described_class.open_timeout + described_class.read_timeout

      expect(upstream_worst_case).to be < described_class.waiter_cap
      expect(described_class.waiter_cap).to be < described_class.lock_ttl
    end
  end
end
