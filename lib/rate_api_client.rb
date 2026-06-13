class RateApiClient
  include HTTParty
  base_uri ENV.fetch('RATE_API_URL', 'http://localhost:8080')
  headers "Content-Type" => "application/json"
  headers 'token' => ENV.fetch('RATE_API_TOKEN', '04aa6f42aa03f220c2ae9a276cd68c62')

  # Raised for every upstream transport failure (timeout, connection, non-2xx).
  # `kind` lets logs/metrics group by failure type; `status` is the HTTP code
  # when there was a response. The original exception is preserved as `cause`
  # (Ruby sets it automatically when raising inside a rescue).
  class UpstreamError < StandardError
    attr_reader :kind, :status

    def initialize(kind:, status: nil)
      @kind = kind
      @status = status
      super("upstream #{kind}#{" (HTTP #{status})" if status}")
    end
  end

  def self.get_rate(period:, hotel:, room:)
    params = {
      attributes: [
        {
          period: period,
          hotel: hotel,
          room: room
        }
      ]
    }.to_json
    self.post("/pricing", body: params)
  end

  # Batch fetch: POSTs all requested combinations in one call and returns the raw
  # 2xx body. The bang signals it raises on protocol-level failure: a non-2xx
  # status, or a 200 carrying the upstream's {"status":"error"} envelope (this
  # API returns 200 even for failures). It does not validate the rates payload
  # itself; shape, combo count, and rate values are BatchValidator's job. No
  # retries (see docs/design.md). Timeouts default to PricingConfig (single
  # source of truth) and can be overridden by the caller.
  def self.fetch_all!(attributes:, open_timeout: PricingConfig.open_timeout, read_timeout: PricingConfig.read_timeout)
    response = post(
      "/pricing",
      body: { attributes: attributes }.to_json,
      open_timeout: open_timeout,
      read_timeout: read_timeout
    )

    unless response.success?
      raise UpstreamError.new(kind: status_kind(response.code), status: response.code)
    end

    # A 200 alone is not success: this upstream flags failures with a
    # {"status":"error"} body, so treat that envelope as an upstream failure.
    if error_envelope?(response.body)
      raise UpstreamError.new(kind: :error_response, status: response.code)
    end

    response.body
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise UpstreamError.new(kind: :timeout)
  rescue SocketError, SystemCallError
    raise UpstreamError.new(kind: :connection)
  end

  def self.status_kind(code)
    case code
    when 401, 403 then :unauthorized
    when 429 then :rate_limited
    when 500..599 then :server_error
    else :unexpected_status
    end
  end
  private_class_method :status_kind

  # This upstream signals errors with a {"status":"error"} body on a 200, so a
  # 200 alone does not mean success. This peeks for that envelope only; the
  # authoritative parse and validation of the rates payload stays in
  # BatchValidator, and an unparseable body is left for it to reject.
  def self.error_envelope?(body)
    parsed = JSON.parse(body)
    parsed.is_a?(Hash) && parsed["status"] == "error"
  rescue JSON::ParserError
    false
  end
  private_class_method :error_envelope?
end
