require 'rails_helper'

describe ManualForecast, type: :model do
  subject(:manual_forecast) { create(:manual_forecast) }

  describe 'FactoryBot' do
    specify { expect(manual_forecast).to be_valid }
    specify { expect(manual_forecast.amount).to eq(Money.from_amount(600.00)) }
  end

  describe '#month' do
    # A forecast is about a month, not a day in it. Without this, 1-Mar and 17-Mar would be two
    # predictions for March and the unique index below would not stop them.
    it 'is filed under the first of the month, whatever day is given' do
      manual_forecast.update!(month: Date.new(2026, 3, 17))

      expect(manual_forecast.reload.month).to eq(Date.new(2026, 3, 1))
    end

    it 'allows only one figure per category per month' do
      duplicate = build(:manual_forecast, category: manual_forecast.category,
                                          month: manual_forecast.month.end_of_month)

      expect(duplicate).not_to be_valid
    end

    it 'allows the same category a figure in another month' do
      next_month = build(:manual_forecast, category: manual_forecast.category,
                                           month: manual_forecast.month.next_month)

      expect(next_month).to be_valid
    end
  end

  describe '#amount' do
    # Zero says "nothing on Holidays in March", which is a real prediction.
    it 'accepts nothing at all as a prediction' do
      manual_forecast.amount = Money.from_amount(0)

      expect(manual_forecast).to be_valid
    end

    # Negative would be income by another name, and the forecast deals in spend as a positive magnitude.
    it 'refuses a negative prediction' do
      manual_forecast.amount = Money.from_amount(-10.00)

      expect(manual_forecast).not_to be_valid
    end
  end

  # The reader may enter a figure, change the method, and change their mind back. Refusing the mismatch
  # would lose the figure; keeping it means switching back restores it.
  it 'is content to belong to a category no longer forecast by hand' do
    manual_forecast.category.update!(forecast_method: :monthly_average)

    expect(manual_forecast.reload).to be_valid
  end
end
