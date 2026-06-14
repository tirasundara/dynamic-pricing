require 'rails_helper'

RSpec.describe BatchValidator do
  # The full attribute space: 4 periods x 3 hotels x 3 rooms = 36 combos.
  let(:periods) { %w[Summer Autumn Winter Spring] }
  let(:hotels)  { %w[FloatingPointResort GitawayHotel RecursionRetreat] }
  let(:rooms)   { %w[SingletonRoom BooleanTwin RestfulKing] }
  let(:expected) do
    periods.product(hotels, rooms).map { |p, h, r| { period: p, hotel: h, room: r } }
  end

  def body(rows) = { rates: rows }.to_json

  # A complete, well-formed batch: one row per expected combo
  def valid_rows
    expected.each_with_index.map do |combo, i|
      { period: combo[:period], hotel: combo[:hotel], room: combo[:room], rate: 10000 + i * 100 }
    end
  end

  it 'covers exactly 36 combos' do
    expect(expected.size).to eq(36)
  end

  describe '.call' do
    context 'with a complete, well-formed 36-combo batch' do
      it 'is valid and maps every combo to its rate as a string' do
        result = described_class.call(body(valid_rows), expected: expected)

        expect(result.valid?).to be(true)
        expect(result.reason).to be_nil
        expect(result.rates.size).to eq(36)
        expect(result.rates.values).to all(match(/\A\d+\z/))
        expect(result.rates['Summer|FloatingPointResort|SingletonRoom']).to eq('10000')
      end

      it 'accepts a rate sent as a digit string and normalizes consistently' do
        rows = valid_rows
        rows[0] = rows[0].merge(rate: '55500')

        result = described_class.call(body(rows), expected: expected)

        expect(result.valid?).to be(true)
        expect(result.rates['Summer|FloatingPointResort|SingletonRoom']).to eq('55500')
      end
    end

    context 'when combos do not match exactly' do
      it 'rejects a missing combo (35 of 36)' do
        result = described_class.call(body(valid_rows[0...-1]), expected: expected)

        expect(result.valid?).to be(false)
        expect(result.reason).to start_with('missing_combos')
      end

      it 'rejects an unexpected extra combo' do
        rows = valid_rows + [{ period: 'Summer', hotel: 'FloatingPointResort', room: 'PenthouseSuite', rate: 100 }]

        result = described_class.call(body(rows), expected: expected)

        expect(result.reason).to start_with('unexpected_combos')
      end

      it 'rejects a duplicated combo' do
        rows = valid_rows
        rows << rows.first

        result = described_class.call(body(rows), expected: expected)

        expect(result.reason).to start_with('duplicate_combo')
      end
    end

    context 'with an invalid rate value' do
      [nil, '', 'abc', -100, 12000.5].each do |bad|
        it "rejects rate #{bad.inspect} and keeps the whole batch out" do
          rows = valid_rows
          rows[0] = rows[0].merge(rate: bad)

          result = described_class.call(body(rows), expected: expected)

          expect(result.valid?).to be(false)
          expect(result.reason).to start_with('invalid_rate')
          expect(result.rates).to eq({})
        end
      end
    end

    context 'with a malformed body' do
      it 'rejects an unparseable body' do
        result = described_class.call('not json', expected: expected)

        expect(result.reason).to eq('unparseable_body')
      end

      it 'rejects a body whose rates is not an array' do
        result = described_class.call({ rates: 'nope' }.to_json, expected: expected)

        expect(result.reason).to eq('missing_rates_array')
      end

      it 'rejects a non-hash row' do
        result = described_class.call(body(['x']), expected: expected)

        expect(result.reason).to eq('malformed_row')
      end

      it 'returns no rates on any rejection' do
        result = described_class.call('not json', expected: expected)

        expect(result.rates).to eq({})
      end
    end
  end
end
