require 'rails_helper'

# The line's contract, which is what keeps the four methods interchangeable on one screen.
describe Forecast::Line, type: :model do
  let(:today) { Date.new(2026, 7, 10) }
  let(:month) { Date.new(2026, 7, 1) }
  let(:data) { ForecastDataBuilder.new(today: today).build }

  subject(:forecast) { Forecast::Month.new(month: month, today: today) }

  def line(name) = forecast.lines.find { |candidate| candidate.label == name }

  before { data }

  # Whatever the method, "spent so far" means the same thing: everything that went out of this category
  # this month. The methods differ over what is still to come, never over what has happened.
  describe '#actual' do
    it 'is the whole category, including spending no method predicted' do
      create(:transaction, account: data.account, category: data.subscriptions, date: month.change(day: 5),
                           description: "A ONE-OFF PLUMBER", amount: Money.from_amount(-120.00))

      expect(line("Subscriptions").actual).to eq(forecast.transactions_for(line("Subscriptions")).sum(&:amount) * -1)
    end
  end

  describe '#projected' do
    it 'is what has gone plus what is still coming, for every method' do
      forecast.lines.reject(&:excluded?).each do |candidate|
        expect(candidate.projected).to eq(candidate.actual + candidate.remaining), candidate.label
      end
    end

    it 'is nothing at all for a category left out of the forecast' do
      expect(line("Transfers").projected).to be_nil
    end
  end

  # Stated against every strategy rather than only the ones with an obvious risk, because it is the one
  # promise the screen makes about the column.
  describe '#remaining' do
    it 'is never negative, whichever way the category is predicted' do
      forecast.lines.reject(&:excluded?).each do |candidate|
        expect(candidate.remaining).to be >= Money.new(0), candidate.label
      end
    end
  end

  describe '#awaiting_figure?' do
    it 'marks a hand-forecast category nobody has given a figure for' do
      expect(line("Holidays")).to be_awaiting_figure
    end

    it 'does not mark a category predicted from its own history' do
      expect(line("Food")).not_to be_awaiting_figure
    end
  end

  describe '#difference' do
    it 'says how far the month ran over the prediction' do
      expect(line("Food").difference).to eq(line("Food").actual - line("Food").expected)
    end
  end
end
