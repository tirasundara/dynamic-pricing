require 'rails_helper'

RSpec.describe Outcome do
  let(:fetched_at) { Time.utc(2026, 6, 14, 12, 0, 0).to_i }

  def outcome(cache_status: :hit)
    described_class.new(rate: '27600', fetched_at: fetched_at, cache_status: cache_status)
  end

  describe '#stale?' do
    it 'is true only for :stale' do
      expect(outcome(cache_status: :stale)).to be_stale
      expect(outcome(cache_status: :hit)).not_to be_stale
      expect(outcome(cache_status: :miss)).not_to be_stale
    end
  end

  describe '#as_of' do
    it 'is the ISO8601 UTC of fetched_at' do
      expect(outcome.as_of).to eq('2026-06-14T12:00:00Z')
    end
  end

  describe '#age' do
    it 'is the number of seconds since fetched_at' do
      travel_to(Time.at(fetched_at + 137)) do
        expect(outcome.age).to eq(137)
      end
    end

    it 'is clamped at 0 for a future fetched_at (clock skew)' do
      travel_to(Time.at(fetched_at - 10)) do
        expect(outcome.age).to eq(0)
      end
    end
  end

  describe 'readers' do
    it 'exposes rate and cache_status' do
      o = outcome(cache_status: :miss)
      expect(o.rate).to eq('27600')
      expect(o.cache_status).to eq(:miss)
    end
  end
end
