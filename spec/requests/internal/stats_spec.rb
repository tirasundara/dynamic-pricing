require 'rails_helper'

RSpec.describe 'GET /internal/stats', type: :request do
  before do
    Rails.cache.clear
    RateCache.store_snapshot(nil)
  end

  def full_rates(rate: 27600)
    Combos.all.to_h { |c| [Combos.key(c[:period], c[:hotel], c[:room]), rate.to_s] }
  end

  it 'reports a fresh cache and the budget counters' do
    RateCache.new.write(full_rates)
    BudgetGate.new.reserve

    get '/internal/stats'

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['redis']).to eq('up')
    expect(body['calls_today']).to eq(1)
    expect(body['calls_remaining']).to eq(PricingConfig.daily_quota - 1)
    expect(body['cache_status']).to eq('fresh')
    expect(body['cache_age_seconds']).to be_a(Integer)
  end

  it 'reports a missing cache when nothing is cached' do
    get '/internal/stats'

    body = JSON.parse(response.body)
    expect(body['calls_today']).to eq(0)
    expect(body['cache_status']).to eq('missing')
    expect(body['cache_age_seconds']).to be_nil
  end

  it 'reports redis down and falls back to the snapshot' do
    RateCache.new.write(full_rates) # populates the snapshot
    allow(Rails.cache).to receive(:read).and_raise(Redis::BaseConnectionError)

    get '/internal/stats'

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['redis']).to eq('down')
    expect(body['cache_status']).to eq('snapshot')
    expect(body['calls_today']).to be_nil
  end
end
