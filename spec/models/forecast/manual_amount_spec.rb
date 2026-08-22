require 'rails_helper'

describe Forecast::ManualAmount, type: :model do
  let(:holidays) { create(:holidays_category) }
  let(:month) { Date.new(2026, 7, 1) }

  def strategy(record) = described_class.new(record: record)

  describe 'where a figure has been given' do
    subject(:manual) { strategy(create(:manual_forecast, category: holidays, month: month, amount: Money.from_amount(800.00))) }

    specify { expect(manual).to be_set }
    specify { expect(manual.expected).to eq(Money.from_amount(800.00)) }

    it 'takes what has been spent off it' do
      expect(manual.remaining(Money.from_amount(300.00))).to eq(Money.from_amount(500.00))
    end

    it 'never goes below nothing, however far the holiday overran' do
      expect(manual.remaining(Money.from_amount(1200.00))).to eq(Money.from_amount(0))
    end
  end

  describe 'where nobody has said' do
    subject(:manual) { strategy(nil) }

    # The distinction the screen leans on: "not set" is not the same statement as "£0.00", which would
    # claim a prediction of nothing had been made deliberately.
    specify { expect(manual).not_to be_set }
    specify { expect(manual.expected).to eq(Money.from_amount(0)) }

    it 'expects nothing further, rather than guessing' do
      expect(manual.remaining(Money.from_amount(300.00))).to eq(Money.from_amount(0))
    end
  end
end
