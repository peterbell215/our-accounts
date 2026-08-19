require 'rails_helper'

describe Forecast::MonthlyAverage, type: :model do
  # A fixed "today" mid-month, so every example says what situation it is testing rather than depending
  # on when the suite happens to run. Nothing here freezes the clock.
  let(:today) { Date.new(2026, 7, 10) }
  let(:month) { Date.new(2026, 7, 1) }
  let(:account) { create(:lloyds_account, opening_date: Date.new(2024, 1, 1)) }
  let(:food) { create(:food_category) }

  # @param [Integer] months_ago 1 is the month before the one being forecast
  def spend(months_ago, amount, category: food, date: nil)
    create(:transaction, account: account, category: category,
                         date: date || (month << months_ago).change(day: 15),
                         description: "TESCO STORES 2889", amount: Money.from_amount(-amount))
  end

  def average(months: 6, category: food)
    history = Forecast::History.new(month: month, today: today, categories: [ category ])

    described_class.new(rows: history.rows_for(category.id), history: history, months: months)
  end

  describe '#expected' do
    it 'is the mean of the complete months before the one being forecast' do
      6.downto(1) { |ago| spend(ago, 100.00) }

      expect(average.expected).to eq(Money.from_amount(100.00))
    end

    # Including the month under way would drag every prediction down by however far through it we are.
    it 'leaves the month being forecast out of its own average' do
      6.downto(1) { |ago| spend(ago, 100.00) }
      spend(0, 5000.00)

      expect(average.expected).to eq(Money.from_amount(100.00))
    end

    it 'looks back no further than the lookback it is given' do
      spend(7, 6000.00)
      6.downto(1) { |ago| spend(ago, 100.00) }

      expect(average(months: 6).expected).to eq(Money.from_amount(100.00))
      expect(average(months: 3).expected).to eq(Money.from_amount(100.00))
    end

    # The requirement in its own words: a month the household genuinely spent nothing in did happen, and
    # should pull the average down.
    it 'counts a month with no spending in it as a month of nothing' do
      spend(6, 600.00)

      expect(average.expected).to eq(Money.from_amount(100.00))
    end

    it 'ignores income and refunds' do
      6.downto(1) { |ago| spend(ago, 100.00) }
      create(:transaction, account: account, category: food, date: (month << 2).change(day: 20),
                           description: "TESCO REFUND", amount: Money.from_amount(500.00))

      expect(average.expected).to eq(Money.from_amount(100.00))
    end

    it 'is nothing at all where there is no history to average' do
      expect(average.expected).to eq(Money.from_amount(0))
    end
  end

  # The divisor is the whole question, and it is settled on how far the *records* go back rather than on
  # how long this category has existed.
  describe '#divisor' do
    it 'is the whole lookback where the records cover it' do
      spend(6, 100.00)

      expect(average.divisor).to eq(6)
    end

    it 'is only the months the records cover where they start inside the lookback' do
      # The first transaction anywhere is three months before the month being forecast.
      spend(3, 300.00)

      expect(average.divisor).to eq(3)
      expect(average.expected).to eq(Money.from_amount(100.00))
    end

    # Dividing by the months *this category* has existed for would make one £600 transaction four months
    # ago predict £600 every month for ever.
    it 'is not shortened by the category being younger than the records' do
      create(:transaction, account: account, category: create(:category), date: (month << 6).change(day: 4),
                           description: "SOMETHING ELSE", amount: Money.from_amount(-10.00))
      spend(1, 600.00)

      expect(average.divisor).to eq(6)
      expect(average.expected).to eq(Money.from_amount(100.00))
    end

    it 'is nothing where there are no transactions at all' do
      expect(average.divisor).to be_zero
    end
  end

  # Without this clamp a forecast three months out averages over months that have not happened, each
  # contributing nothing and dragging the prediction down by a third.
  describe 'a month in the future' do
    let(:month) { Date.new(2026, 10, 1) }

    it 'averages the months that have actually happened, not the ones between' do
      6.downto(1) { |ago| spend(ago, 100.00, date: (Date.new(2026, 7, 1) << ago).change(day: 15)) }

      expect(average.expected).to eq(Money.from_amount(100.00))
    end
  end

  describe '#remaining' do
    before { 6.downto(1) { |ago| spend(ago, 100.00) } }

    it 'is what is left of the prediction' do
      expect(average.remaining(Money.from_amount(30.00))).to eq(Money.from_amount(70.00))
    end

    it 'never goes below nothing, however far the month has overspent' do
      expect(average.remaining(Money.from_amount(500.00))).to eq(Money.from_amount(0))
    end
  end

  describe '#window_months' do
    it 'names every month in the lookback with what was spent in it, zeroes included' do
      spend(2, 50.00)

      expect(average.window_months.count).to eq(6)
      expect(average.window_months.map(&:first)).to include(Date.new(2026, 5, 1))
      expect(average.window_months.to_h[Date.new(2026, 5, 1)]).to eq(Money.from_amount(50.00))
      expect(average.window_months.to_h[Date.new(2026, 4, 1)]).to eq(Money.from_amount(0))
    end
  end
end
