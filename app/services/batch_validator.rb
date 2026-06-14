# BatchValidator validates a raw upstream batch body against the combos we requested.
#
# fetch_all! has already turned transport failures and the upstream's 200
# {"status":"error"} envelope into UpstreamError, so BatchValidator only sees
# genuine 2xx payloads. It still guards unparseable/missing-rates defensively.
module BatchValidator
  extend self

  # Outcome of a validation. valid? is derived (no reason means valid).
  Result = Data.define(:rates, :reason) do
    def self.ok(rates) = new(rates: rates, reason: nil)
    def self.invalid(reason) = new(rates: {}, reason: reason)
    def valid? = reason.nil?
  end

  # All-or-nothing. Returns Result.ok(rates) only if the body parses to
  # {"rates" => [...]}, the rows cover exactly the expected combos (none missing,
  # extra, or duplicated), and every rate is a non-negative integer (accepted as
  # a JSON number or a digit string, normalized to a digit string). Otherwise
  # Result.invalid(reason), where reason is a short, loggable tag.
  #
  # expected: the requested combo hashes, [{ period:, hotel:, room: }, ...].
  def call(raw_body, expected:)
    parsed = parse(raw_body)
    return Result.invalid("unparseable_body") if parsed.nil?
    return Result.invalid("missing_rates_array") unless parsed.is_a?(Hash) && parsed["rates"].is_a?(Array)

    rates = {}
    parsed["rates"].each do |row|
      return Result.invalid("malformed_row") unless row.is_a?(Hash)

      key = Combos.key(row["period"], row["hotel"], row["room"])
      return Result.invalid("duplicate_combo:#{key}") if rates.key?(key)

      rate = normalize_rate(row["rate"])
      return Result.invalid("invalid_rate:#{row["rate"].inspect}") if rate.nil?

      rates[key] = rate
    end

    expected_keys = expected.map { |c| Combos.key(c[:period], c[:hotel], c[:room]) }
    missing = expected_keys - rates.keys
    extra = rates.keys - expected_keys
    return Result.invalid("missing_combos:#{missing.size}") if missing.any?
    return Result.invalid("unexpected_combos:#{extra.size}") if extra.any?

    Result.ok(rates)
  end

  private

  def parse(raw_body)
    JSON.parse(raw_body)
  rescue JSON::ParserError, TypeError
    nil
  end

  # JSON number or digit string -> digit string for a non-negative integer;
  # nil (invalid) for null, negative, float, or non-numeric values.
  def normalize_rate(value)
    case value
    when Integer then value.negative? ? nil : value.to_s
    when String then value.match?(/\A\d+\z/) ? value : nil
    end
  end
end
