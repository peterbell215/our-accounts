require 'rails_helper'

describe Forecast::Month, type: :model do
  let(:today) { Date.new(2026, 7, 10) }
  let(:month) { Date.new(2026, 7, 1) }
  let(:data) { ForecastDataBuilder.new(today: today).build }

  subject(:forecast) { described_class.new(month: month, today: today) }

  def line(name) = forecast.lines.find { |candidate| candidate.label == name }

  describe '#lines' do
    before { data }

    it 'has a line for every category' do
      expect(forecast.lines.map(&:label)).to include("Food", "Subscriptions", "Holidays", "Transfers")
    end

    # About a third of real transactions have no category. Left out, the headline total would be a third
    # short with nothing on the page to say so.
    it 'gives everything uncategorised a line of its own, last' do
      expect(forecast.lines.last.label).to eq("Uncategorised")
      expect(forecast.lines.last).to be_uncategorised
      expect(line("Uncategorised").actual).to eq(Money.from_amount(80.00))
    end

    it 'predicts the uncategorised line by average, there being no structure in it to exploit' do
      expect(line("Uncategorised").method).to eq(:monthly_average)
    end

    it 'names the categories in alphabetical order' do
      names = forecast.lines.reject(&:uncategorised?).map(&:label)

      expect(names).to eq(names.sort)
    end
  end

  describe 'the totals' do
    before { data }

    # Paying off a card is money moved, not money spent — the spending already happened on the card.
    it 'leave an excluded category out entirely' do
      expect(line("Transfers").actual).to eq(Money.from_amount(500.00))
      expect(line("Transfers").expected).to be_nil
      expect(forecast.actual).to eq(forecast.lines.reject(&:excluded?).sum(Money.new(0), &:actual))
    end

    it 'add up the lines that are forecast' do
      expected = forecast.lines.reject(&:excluded?).sum(Money.new(0), &:expected)

      expect(forecast.expected).to eq(expected)
    end

    it 'ignore income' do
      expect(forecast.actual).to be_positive
      expect(forecast.lines.map(&:actual)).to all(be >= Money.new(0))
    end
  end

  describe '#awaiting_figures' do
    before { data }

    # Much the likeliest way for the headline total to be quietly too small, so the screen says so.
    it 'names the hand-forecast categories nobody has given a figure for' do
      expect(forecast.awaiting_figures.map(&:label)).to eq([ "Holidays" ])
    end

    it 'is empty once a figure has been given' do
      create(:manual_forecast, category: data.holidays, month: month, amount: Money.from_amount(600.00))

      expect(forecast.awaiting_figures).to be_empty
      expect(line("Holidays").expected).to eq(Money.from_amount(600.00))
    end
  end

  describe 'where the month sits' do
    it 'is the current month' do
      expect(forecast).to be_current
      expect(forecast).not_to be_past
      expect(forecast).not_to be_future
    end

    it 'knows a month that has finished' do
      expect(described_class.new(month: Date.new(2026, 5, 1), today: today)).to be_past
    end

    it 'knows a month that has not started' do
      expect(described_class.new(month: Date.new(2026, 9, 1), today: today)).to be_future
    end

    it 'steps a month either way' do
      expect(forecast.previous).to eq(Date.new(2026, 6, 1))
      expect(forecast.next).to eq(Date.new(2026, 8, 1))
    end
  end

  describe 'the bounds the navigation is held within' do
    before { data }

    it 'reaches back no further than the first transaction' do
      expect(described_class.earliest_month(today)).to eq(Transaction.minimum(:date).beginning_of_month)
    end

    it 'reaches forward a year, beyond which the average window holds nothing that has happened' do
      expect(described_class.latest_month(today)).to eq(Date.new(2027, 7, 1))
    end
  end

  describe 'an empty database' do
    it 'still lists every category, at nothing' do
      create(:food_category)

      expect(forecast).not_to be_any_transactions
      expect(line("Food").expected).to eq(Money.from_amount(0))
      expect(forecast.expected).to eq(Money.from_amount(0))
    end

    it 'holds the navigation to this month, there being nothing to look back at' do
      expect(described_class.earliest_month(today)).to eq(month)
    end
  end

  describe '#transactions_for' do
    before { data }

    it "lists a line's own spending this month, newest first" do
      transactions = forecast.transactions_for(line("Subscriptions"))

      expect(transactions.map(&:description)).to all(match(/OCTOPUS|WATER|STREAMING/))
      expect(transactions.map(&:date)).to eq(transactions.map(&:date).sort.reverse)
    end

    it 'finds the uncategorised line its own rows' do
      expect(forecast.transactions_for(forecast.uncategorised_line).map(&:description))
        .to all(eq("SOMETHING UNFILED"))
    end
  end
end
