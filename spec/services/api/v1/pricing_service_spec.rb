require 'rails_helper'

RSpec.describe Api::V1::PricingService do
  subject(:service) { described_class.new(period: period, hotel: hotel, room: room) }

  let(:period) { 'Summer' }
  let(:hotel)  { 'FloatingPointResort' }
  let(:room)   { 'SingletonRoom' }
  let(:key)    { Combos.key(period, hotel, room) }

  before do
    Rails.cache.clear
    RateCache.store_snapshot(nil)
  end

  def upstream_url = "#{RateApiClient.base_uri}/pricing"

  # A complete 36-combo upstream response, every combo carrying the same rate.
  def stub_upstream(rate: 27600, status: 200)
    rows = Combos.all.map { |c| c.merge(rate: rate) }
    stub_request(:post, upstream_url).to_return(status: status, body: { rates: rows }.to_json)
  end

  # A complete 36-combo rates map for pre-seeding the cache.
  def full_rates(rate: 27600)
    Combos.all.to_h { |c| [Combos.key(c[:period], c[:hotel], c[:room]), rate.to_s] }
  end

  def seed_cache(rate:, at:)
    travel_to(at) { RateCache.new.write(full_rates(rate: rate)) }
  end

  context 'on a fresh cache hit' do
    it 'serves the cached rate without calling upstream' do
      RateCache.new.write(full_rates(rate: 15000))

      service.run

      expect(service).to be_valid
      expect(service.result.cache_status).to eq(:hit)
      expect(service.result.stale?).to be(false)
      expect(service.result.rate).to eq('15000')
      expect(WebMock).not_to have_requested(:post, upstream_url)
    end
  end

  context 'on a cold miss' do
    it 'refreshes and serves the new rate as a miss' do
      stub_upstream(rate: 20000)

      service.run

      expect(service).to be_valid
      expect(service.result.cache_status).to eq(:miss)
      expect(service.result.rate).to eq('20000')
      expect(WebMock).to have_requested(:post, upstream_url)
    end

    it 'returns a 503 reason when upstream fails and there is nothing cached' do
      stub_upstream(status: 500)

      service.run

      expect(service).not_to be_valid
      expect(service.errors.join).to match(/unavailable/i)
    end
  end

  context 'on a stale entry' do
    let(:base) { Time.utc(2026, 6, 14, 12, 0, 0) }

    it 'refreshes and serves the new rate as a miss' do
      seed_cache(rate: 10000, at: base)
      stub_upstream(rate: 30000)

      travel_to(base + 301) { service.run }

      expect(service.result.cache_status).to eq(:miss)
      expect(service.result.rate).to eq('30000')
    end

    it 'serves stale when the upstream fails during refresh' do
      seed_cache(rate: 10000, at: base)
      stub_upstream(status: 500)

      travel_to(base + 400) { service.run }

      expect(service).to be_valid
      expect(service.result.cache_status).to eq(:stale)
      expect(service.result.stale?).to be(true)
      expect(service.result.rate).to eq('10000')
    end

    it 'serves stale and keeps the cache when the batch is invalid (35/36)' do
      seed_cache(rate: 10000, at: base)
      rows = Combos.all.first(35).map { |c| c.merge(rate: 99) }
      stub_request(:post, upstream_url).to_return(status: 200, body: { rates: rows }.to_json)

      travel_to(base + 400) { service.run }

      expect(service.result.cache_status).to eq(:stale)
      expect(service.result.rate).to eq('10000')
    end

    it 'skips upstream and serves stale when the budget is exhausted' do
      allow(PricingConfig).to receive(:budget_limit).and_return(0)
      seed_cache(rate: 10000, at: base)

      travel_to(base + 400) { service.run }

      expect(service.result.cache_status).to eq(:stale)
      expect(service.result.rate).to eq('10000')
      expect(WebMock).not_to have_requested(:post, upstream_url)
    end
  end

  context 'when Redis is down' do
    it 'serves the L1 snapshot as stale and never calls upstream' do
      RateCache.new.write(full_rates(rate: 10000)) # populates the snapshot
      allow(Rails.cache).to receive(:read).and_raise(Redis::BaseConnectionError)

      service.run

      expect(service).to be_valid
      expect(service.result.cache_status).to eq(:stale)
      expect(service.result.rate).to eq('10000')
      expect(WebMock).not_to have_requested(:post, upstream_url)
    end

    it 'returns a 503 reason when there is no snapshot' do
      allow(Rails.cache).to receive(:read).and_raise(Redis::BaseConnectionError)

      service.run

      expect(service).not_to be_valid
      expect(service.errors.join).to match(/unavailable/i)
    end
  end
end
