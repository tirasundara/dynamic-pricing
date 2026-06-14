class Api::V1::PricingController < ApplicationController
  before_action :validate_params

  def index
    service = Api::V1::PricingService.new(
      period: params[:period],
      hotel: params[:hotel],
      room: params[:room],
      request_id: request.request_id
    )
    service.run

    if service.valid?
      render_rate(service.result)
    else
      render json: { error: service.errors.join(', ') }, status: :service_unavailable
    end
  end

  private

  # Uniform success body in all modes (fresh and stale), plus infra-layer headers.
  def render_rate(outcome)
    response.set_header("Age", outcome.age.to_s)
    response.set_header("X-Cache-Status", outcome.cache_status.to_s)
    render json: { rate: outcome.rate, stale: outcome.stale?, as_of: outcome.as_of }
  end

  def validate_params
    if params[:period].blank? || params[:hotel].blank? || params[:room].blank?
      return invalid_input(:missing_params, "Missing required parameters: period, hotel, room")
    end

    unless Combos::PERIODS.include?(params[:period])
      return invalid_input(:invalid_period, "Invalid period. Must be one of: #{Combos::PERIODS.join(', ')}")
    end

    unless Combos::HOTELS.include?(params[:hotel])
      return invalid_input(:invalid_hotel, "Invalid hotel. Must be one of: #{Combos::HOTELS.join(', ')}")
    end

    unless Combos::ROOMS.include?(params[:room])
      return invalid_input(:invalid_room, "Invalid room. Must be one of: #{Combos::ROOMS.join(', ')}")
    end
  end

  def invalid_input(reason, message)
    ActiveSupport::Notifications.instrument(
      "invalid_input.pricing",
      request_id: request.request_id,
      reason: reason,
      period: params[:period],
      hotel: params[:hotel],
      room: params[:room]
    )
    render json: { error: message }, status: :bad_request
  end
end
