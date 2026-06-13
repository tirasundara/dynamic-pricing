require 'rails_helper'

# These specs port the original scaffold Minitest cases
# (test/controllers/pricing_controller_test.rb) assertion-for-assertion,
# proving the API contract survived the move to RSpec before any behavior
# change. They exercise the existing controller/service, which still calls
# RateApiClient.get_rate; the happy-path and upstream-failure cases will be
# revised when batching lands.
RSpec.describe 'Api::V1::Pricing', type: :request do
  describe 'GET /api/v1/pricing' do
    let(:valid_params) do
      { period: 'Summer', hotel: 'FloatingPointResort', room: 'SingletonRoom' }
    end

    context 'with all valid parameters' do
      it 'returns the rate' do
        body = { 'rates' => [{ 'period' => 'Summer', 'hotel' => 'FloatingPointResort',
                               'room' => 'SingletonRoom', 'rate' => '15000' }] }.to_json
        allow(RateApiClient).to receive(:get_rate).and_return(double(success?: true, body: body))

        get api_v1_pricing_path, params: valid_params

        expect(response).to have_http_status(:success)
        expect(response.media_type).to eq('application/json')
        expect(JSON.parse(response.body)['rate']).to eq('15000')
      end
    end

    context 'when the rate API fails' do
      it 'returns a 400 with the upstream error message' do
        allow(RateApiClient).to receive(:get_rate)
          .and_return(double(success?: false, body: { 'error' => 'Rate not found' }))

        get api_v1_pricing_path, params: valid_params

        expect(response).to have_http_status(:bad_request)
        expect(response.media_type).to eq('application/json')
        expect(JSON.parse(response.body)['error']).to include('Rate not found')
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
        expect(response.media_type).to eq('application/json')
        expect(JSON.parse(response.body)['error']).to include('Missing required parameters')
      end
    end

    context 'with an invalid period' do
      it 'returns a 400 invalid-period error' do
        get api_v1_pricing_path, params: valid_params.merge(period: 'summer-2024')

        expect(response).to have_http_status(:bad_request)
        expect(response.media_type).to eq('application/json')
        expect(JSON.parse(response.body)['error']).to include('Invalid period')
      end
    end

    context 'with an invalid hotel' do
      it 'returns a 400 invalid-hotel error' do
        get api_v1_pricing_path, params: valid_params.merge(hotel: 'InvalidHotel')

        expect(response).to have_http_status(:bad_request)
        expect(response.media_type).to eq('application/json')
        expect(JSON.parse(response.body)['error']).to include('Invalid hotel')
      end
    end

    context 'with an invalid room' do
      it 'returns a 400 invalid-room error' do
        get api_v1_pricing_path, params: valid_params.merge(room: 'InvalidRoom')

        expect(response).to have_http_status(:bad_request)
        expect(response.media_type).to eq('application/json')
        expect(JSON.parse(response.body)['error']).to include('Invalid room')
      end
    end
  end
end
