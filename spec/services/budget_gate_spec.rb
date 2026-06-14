require 'rails_helper'

RSpec.describe BudgetGate do
  subject(:gate) { described_class.new }

  before { Rails.cache.clear }

  describe '#reserve' do
    before { allow(PricingConfig).to receive(:budget_limit).and_return(3) }

    it 'allows attempts up to the limit, counting each' do
      expect(Array.new(3) { gate.reserve }).to eq([true, true, true])
      expect(gate.count).to eq(3)
    end

    it 'gates at the limit and does not inflate the counter' do
      3.times { gate.reserve }

      expect(gate.reserve).to be(false)
      expect(gate.reserve).to be(false)
      expect(gate.count).to eq(3)
    end
  end

  describe '#count' do
    it 'is zero before any reserve' do
      expect(gate.count).to eq(0)
    end
  end

  describe '#remaining' do
    it 'is daily_quota minus count' do
      allow(PricingConfig).to receive(:daily_quota).and_return(5)
      2.times { gate.reserve }

      expect(gate.remaining).to eq(3)
    end

    it 'never goes negative' do
      allow(PricingConfig).to receive(:daily_quota).and_return(2)
      allow(PricingConfig).to receive(:budget_limit).and_return(5)
      4.times { gate.reserve }

      expect(gate.remaining).to eq(0)
    end
  end

  describe '#warn?' do
    before { allow(PricingConfig).to receive(:budget_warn).and_return(2) }

    it 'is false below the threshold and true at or above it' do
      expect(gate.warn?).to be(false)
      2.times { gate.reserve }
      expect(gate.warn?).to be(true)
    end
  end

  describe 'daily reset (UTC date key)' do
    it 'starts fresh on a new UTC day' do
      travel_to(Time.utc(2026, 6, 14, 23, 59, 0)) do
        3.times { gate.reserve }

        expect(gate.count).to eq(3)
      end

      travel_to(Time.utc(2026, 6, 15, 0, 1, 0)) do
        expect(gate.count).to eq(0)
      end
    end
  end

  describe 'Redis unavailable' do
    it 'raises UnavailableError when the counter read fails' do
      allow(Rails.cache).to receive(:read).and_raise(Redis::BaseConnectionError)

      expect { gate.count }.to raise_error(RedisBacked::UnavailableError)
    end

    it 'raises UnavailableError when the increment fails' do
      allow(Rails.cache).to receive(:increment).and_raise(Redis::BaseConnectionError)

      expect { gate.reserve }.to raise_error(RedisBacked::UnavailableError)
    end
  end
end
