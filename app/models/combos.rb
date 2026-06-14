# The canonical attribute space (4 periods x 3 hotels x 3 rooms = 36 combos) and
# the shared combo-key derivation. Single source of truth for the valid sets,
# the full combo list (what we request from upstream and validate against), and
# the cache-key format, so BatchValidator, PricingService, and the controller
# can't drift.
module Combos
  PERIODS = %w[Summer Autumn Winter Spring].freeze
  HOTELS  = %w[FloatingPointResort GitawayHotel RecursionRetreat].freeze
  ROOMS   = %w[SingletonRoom BooleanTwin RestfulKing].freeze

  ALL = PERIODS.product(HOTELS, ROOMS).map do |period, hotel, room|
    { period: period, hotel: hotel, room: room }
  end.freeze

  module_function

  # The 36 requested combos.
  def all = ALL

  # Cache/lookup key for a combo. Case-sensitive raw join; values are already the
  # canonical enums (controller-validated, upstream echoes the same case), and no
  # value contains "|", so the separator is unambiguous.
  def key(period, hotel, room) = "#{period}|#{hotel}|#{room}"

  def valid?(period, hotel, room)
    PERIODS.include?(period) && HOTELS.include?(hotel) && ROOMS.include?(room)
  end
end
