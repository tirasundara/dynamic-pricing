require 'rails_helper'

RSpec.describe RateApiClient do
  # Derive the URL from the client's configured base_uri so the spec is
  # independent of RATE_API_URL (the compose env sets it to rate-api:8080).
  let(:url) { "#{described_class.base_uri}/pricing" }
  let(:attributes) do
    [{ period: 'Summer', hotel: 'FloatingPointResort', room: 'SingletonRoom' }]
  end

  # Exercises the default timeouts (from PricingConfig) by omitting them.
  def fetch
    described_class.fetch_all!(attributes: attributes)
  end

  describe '.fetch_all!' do
    context 'on a 2xx response' do
      it 'returns the raw body verbatim' do
        body = '{"rates":[{"period":"Summer","hotel":"FloatingPointResort","room":"SingletonRoom","rate":27600}]}'
        stub_request(:post, url).to_return(status: 200, body: body)

        expect(fetch).to eq(body)
      end

      it 'accepts explicit timeout overrides' do
        stub_request(:post, url).to_return(status: 200, body: '{}')

        expect(
          described_class.fetch_all!(attributes: attributes, open_timeout: 1, read_timeout: 1)
        ).to eq('{}')
      end

      it 'returns a non-JSON 200 body unchanged (not an error envelope; BatchValidator validates)' do
        stub_request(:post, url).to_return(status: 200, body: 'not json')

        expect(fetch).to eq('not json')
      end

      it 'returns a 200 that lacks rates but is not an error envelope (BatchValidator decides)' do
        stub_request(:post, url).to_return(status: 200, body: '{"rates":[]}')

        expect(fetch).to eq('{"rates":[]}')
      end

      it 'sends the attributes batch and the auth token' do
        stub_request(:post, url).to_return(status: 200, body: '{}')

        fetch

        expect(WebMock).to have_requested(:post, url)
          .with(headers: { 'token' => '04aa6f42aa03f220c2ae9a276cd68c62' },
                body: { attributes: attributes }.to_json)
      end
    end

    context 'on a 200 carrying an error envelope' do
      # The upstream returns 200 even for failures, flagged by {"status":"error"};
      # observed on valid requests, not just invalid ones.
      it 'raises UpstreamError(:error_response) instead of returning the body' do
        stub_request(:post, url).to_return(
          status: 200,
          body: '{"message":"Failed to process rates due to an intermittent issue.","status":"error"}'
        )

        expect { fetch }.to raise_error(RateApiClient::UpstreamError) do |e|
          expect(e.kind).to eq(:error_response)
          expect(e.status).to eq(200)
        end
      end
    end

    context 'on transport failures' do
      it 'raises UpstreamError(:timeout) on a request timeout' do
        stub_request(:post, url).to_timeout

        expect { fetch }.to raise_error(RateApiClient::UpstreamError) do |e|
          expect(e.kind).to eq(:timeout)
          expect(e.status).to be_nil
        end
      end

      it 'preserves the original timeout as cause' do
        stub_request(:post, url).to_timeout

        expect { fetch }.to raise_error(RateApiClient::UpstreamError) do |e|
          expect(e.cause).not_to be_nil
        end
      end

      it 'raises UpstreamError(:connection) on a connection error' do
        stub_request(:post, url).to_raise(Errno::ECONNREFUSED)

        expect { fetch }.to raise_error(RateApiClient::UpstreamError) do |e|
          expect(e.kind).to eq(:connection)
          expect(e.status).to be_nil
        end
      end
    end

    context 'on non-2xx responses' do
      # 429, 500, and 401 bodies are the real upstream responses captured locally.
      # 503, 404, and 403 are synthetic: fetch_all! branches on the status code,
      # not the body, so the body is irrelevant here, they just cover the mapping
      # ranges (auth, 5xx, and other-non-2xx).
      {
        401 => [:unauthorized, '{"error":"Unauthorized"}'],
        403 => [:unauthorized, '{"error":"Forbidden"}'],
        429 => [:rate_limited, '{"error":"Rate limit exceeded (1000/day)"}'],
        500 => [:server_error, '{"error":"An unexpected internal error occurred"}'],
        503 => [:server_error, '{"error":"Service Unavailable"}'],
        404 => [:unexpected_status, '{"error":"Not Found"}']
      }.each do |status, (kind, body)|
        it "raises UpstreamError(#{kind.inspect}, status: #{status})" do
          stub_request(:post, url).to_return(status: status, body: body)

          expect { fetch }.to raise_error(RateApiClient::UpstreamError) do |e|
            expect(e.kind).to eq(kind)
            expect(e.status).to eq(status)
          end
        end
      end
    end
  end
end
