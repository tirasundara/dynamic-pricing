require 'rails_helper'

RSpec.describe CacheEntry do
  let(:fresh_window) { 300 }
  let(:max_stale)    { 3600 }
  let(:fetched_at)   { Time.utc(2026, 6, 14, 12, 0, 0).to_i }

  def entry
    described_class.new(
      rates: { 'Summer|FloatingPointResort|SingletonRoom' => '27600' },
      fetched_at: fetched_at,
      fresh_window: fresh_window,
      max_stale: max_stale
    )
  end

  # Runs the block with the clock set `seconds` after fetched_at.
  def at_age(seconds, &block) = travel_to(Time.at(fetched_at + seconds), &block)

  describe '#status' do
    {
      0    => :fresh,
      299  => :fresh,
      300  => :stale,    # fresh_window boundary: not < 300
      301  => :stale,
      3599 => :stale,
      3600 => :expired,  # max_stale boundary: not < 3600
      3601 => :expired
    }.each do |seconds, expected_status|
      it "is #{expected_status} at age #{seconds}s" do
        at_age(seconds) { expect(entry.status).to eq(expected_status) }
      end
    end
  end

  describe '#age' do
    it 'is the number of seconds since fetched_at' do
      at_age(137) { expect(entry.age).to eq(137) }
    end
  end

  describe 'predicates' do
    it 'fresh? / stale? / expired? agree with status' do
      at_age(100)  { expect(entry).to be_fresh }
      at_age(1000) { expect(entry).to be_stale }
      at_age(4000) { expect(entry).to be_expired }
    end
  end
end
