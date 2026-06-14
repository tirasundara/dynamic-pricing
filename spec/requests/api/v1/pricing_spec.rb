require 'rails_helper'

# Request specs for the pricing endpoint (the live API contract). The five
# validation cases began as ports of the scaffold Minitest tests; the happy-path
# and failure cases were rewritten when batching/caching landed.
RSpec.describe 'Api::V1::Pricing', type: :request do
  describe 'GET /api/v1/pricing' do
    let(:valid_params) do
      { period: 'Summer', hotel: 'FloatingPointResort', room: 'SingletonRoom' }
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

    context 'with all valid parameters (cold miss -> refresh)' do
      it 'returns 200 with the uniform body and cache headers' do
        stub_full_batch(rate: 15000)

        get api_v1_pricing_path, params: valid_params

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq('application/json')

        body = JSON.parse(response.body)
        expect(body['rate']).to eq('15000')
        expect(body['stale']).to be(false)
        expect(body['as_of']).to be_present

        expect(response.headers['X-Cache-Status']).to eq('miss')
        expect(response.headers['Age']).to be_present
      end
    end

    context 'when the upstream fails and nothing is cached' do
      it 'returns 503 with a descriptive error' do
        stub_full_batch(status: 500)

        get api_v1_pricing_path, params: valid_params

        expect(response).to have_http_status(:service_unavailable)
        expect(response.media_type).to eq('application/json')
        expect(JSON.parse(response.body)['error']).to match(/unavailable/i)
      end
    end

    context 'without any parameters' do
      it 'returns a 400 missing-parameters error' do
        get api_v1_pricing_path

        expect(response).to have_http_status(:bad_request)
        expect(response.media_type).to eq('application/json')
        expect(JSON.parse(response.body)['error']).to include('Missing required parameters')
      end
    end

    context 'with empty parameters' do
      it 'returns a 400 missing-parameters error' do
        get api_v1_pricing_path, params: { period: '', hotel: '', room: '' }

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to include('Missing required parameters')
      end
    end

    context 'with an invalid period' do
      it 'returns a 400 invalid-period error' do
        get api_v1_pricing_path, params: valid_params.merge(period: 'summer-2024')

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to include('Invalid period')
      end
    end

    context 'with an invalid hotel' do
      it 'returns a 400 invalid-hotel error' do
        get api_v1_pricing_path, params: valid_params.merge(hotel: 'InvalidHotel')

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to include('Invalid hotel')
      end
    end

    context 'with an invalid room' do
      it 'returns a 400 invalid-room error' do
        get api_v1_pricing_path, params: valid_params.merge(room: 'InvalidRoom')

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to include('Invalid room')
      end
    end
  end
end
