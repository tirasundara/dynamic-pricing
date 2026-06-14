require 'rails_helper'

RSpec.describe 'Pricing instrumentation' do
  subject(:service) do
    Api::V1::PricingService.new(period: 'Summer', hotel: 'FloatingPointResort', room: 'SingletonRoom')
  end

  before do
    Rails.cache.clear
    RateCache.store_snapshot(nil)
  end

  def upstream_url = "#{RateApiClient.base_uri}/pricing"

  def stub_full_batch(rate: 27600, status: 200)
    rows = Combos.all.map { |c| c.merge(rate: rate) }
    stub_request(:post, upstream_url).to_return(status: status, body: { rates: rows }.to_json)
  end

  def full_rates(rate: 27600)
    Combos.all.to_h { |c| [Combos.key(c[:period], c[:hotel], c[:room]), rate.to_s] }
  end

  # Captures the *.pricing events emitted while the block runs.
  def events_during
    captured = []
    sub = ActiveSupport::Notifications.subscribe(/\.pricing$/) do |name, _start, _finish, _id, payload|
      captured << [name.delete_suffix(".pricing"), payload]
    end
    yield
    captured
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  describe 'emit points' do
    it 'emits cache_hit on a fresh hit' do
      RateCache.new.write(full_rates)

      events = events_during { service.run }

      expect(events.map(&:first)).to include("cache_hit")
    end

    it 'emits cache_missed and upstream_call on a cold miss' do
      stub_full_batch

      events = events_during { service.run }

      expect(events.map(&:first)).to include("cache_missed", "upstream_call")
    end

    it 'emits upstream_failure with the failure type when upstream errors' do
      stub_full_batch(status: 500)

      events = events_during { service.run }
      failure = events.find { |name, _| name == "upstream_failure" }

      expect(failure).to be_present
      expect(failure.last[:type]).to eq(:server_error)
    end

    it 'emits stale_served when degrading to stale' do
      base = Time.utc(2026, 6, 14, 12, 0, 0)
      travel_to(base) { RateCache.new.write(full_rates(rate: 10000)) }
      stub_full_batch(status: 500)

      events = travel_to(base + 400) { events_during { service.run } }

      expect(events.map(&:first)).to include("stale_served")
    end

    it 'carries the request_id in the payload' do
      svc = Api::V1::PricingService.new(
        period: 'Summer', hotel: 'FloatingPointResort', room: 'SingletonRoom', request_id: 'req-abc'
      )
      RateCache.new.write(full_rates)

      events = events_during { svc.run }

      expect(events.first.last[:request_id]).to eq('req-abc')
    end
  end

  describe 'the JSON subscriber' do
    it 'logs an event as one JSON line at the mapped level' do
      logged = nil
      allow(Rails.logger).to receive(:error) { |line| logged = line }

      ActiveSupport::Notifications.instrument(
        "upstream_failure.pricing", request_id: "req-1", type: :server_error
      )

      parsed = JSON.parse(logged)
      expect(parsed["event"]).to eq("upstream_failure")
      expect(parsed["type"]).to eq("server_error")
      expect(parsed["request_id"]).to eq("req-1")
      expect(parsed).to include("timestamp", "duration_ms")
    end
  end
end
