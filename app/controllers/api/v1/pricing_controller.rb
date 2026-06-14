class Api::V1::PricingController < ApplicationController
  before_action :validate_params

  def index
    service = Api::V1::PricingService.new(
      period: params[:period],
      hotel: params[:hotel],
      room: params[:room]
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
      return render json: { error: "Missing required parameters: period, hotel, room" }, status: :bad_request
    end

    unless Combos::PERIODS.include?(params[:period])
      return render json: { error: "Invalid period. Must be one of: #{Combos::PERIODS.join(', ')}" }, status: :bad_request
    end

    unless Combos::HOTELS.include?(params[:hotel])
      return render json: { error: "Invalid hotel. Must be one of: #{Combos::HOTELS.join(', ')}" }, status: :bad_request
    end

    unless Combos::ROOMS.include?(params[:room])
      return render json: { error: "Invalid room. Must be one of: #{Combos::ROOMS.join(', ')}" }, status: :bad_request
    end
  end
end
