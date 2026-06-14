# Single subscriber that turns every *.pricing ActiveSupport::Notifications event
# into one structured JSON log line. This is the observability seam: to emit
# metrics, swap Rails.logger here for a StatsD/Prometheus emitter without touching
# any emit site in the business code.
module PricingInstrumentation
  LEVEL = {
    "upstream_failure"  => :error,
    "redis_unavailable" => :error,
    "stale_served"      => :warn,
    "budget_warning"    => :warn,
    "budget_gate_hit"   => :warn,
    "cache_hit"         => :debug
  }.freeze
end

ActiveSupport::Notifications.subscribe(/\.pricing$/) do |name, start, finish, _id, payload|
  event = name.delete_suffix(".pricing")
  line = {
    event: event,
    timestamp: Time.now.utc.iso8601(3),
    duration_ms: ((finish - start) * 1000).round(2),
    **payload
  }
  Rails.logger.public_send(PricingInstrumentation::LEVEL.fetch(event, :info), line.to_json)
end
