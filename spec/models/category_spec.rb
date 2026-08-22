require 'rails_helper'

describe Category, type: :model do
  subject(:category) { create(:category) }

  describe 'FactoryBot' do
    specify { expect(category).to be_valid }
    specify { expect(category.name).to eq("Test Category") }
  end

  describe '#forecast_method' do
    # An unconfigured category has to be forecast somehow, and an average of recent months is the honest
    # generic answer — it assumes nothing about the shape of the spending.
    it 'is an average of recent months until somebody says otherwise' do
      expect(category).to be_forecast_monthly_average
    end

    it 'refuses a method it does not have' do
      category.forecast_method = "wishful_thinking"

      expect(category).not_to be_valid
      expect(category.errors[:forecast_method]).to be_present
    end

    # The enum is declared with `scopes: false`, and this is the regression test for why. Naming the
    # first value `average` — the obvious name — would have generated a `Category.average` scope on top
    # of ActiveRecord::Calculations#average. Suppressing the scopes removes the whole class of collision,
    # so nothing here should have grown a class method named after a value.
    it 'generates no class scopes to collide with ActiveRecord' do
      expect(Category).not_to respond_to(:monthly_average)
      expect(Category).not_to respond_to(:excluded)
      expect(Category.average(:id)).to be_present
    end
  end

  describe '#forecast_window' do
    it 'is six months where the category does not say' do
      expect(category.forecast_window).to eq(6)
    end

    it 'is whatever the category says where it does' do
      category.update!(forecast_months: 12)

      expect(category.forecast_window).to eq(12)
    end

    it 'refuses a lookback of no months, which would divide by zero' do
      category.forecast_months = 0

      expect(category).not_to be_valid
    end

    it 'refuses a lookback longer than the two years anybody has records for' do
      category.forecast_months = 25

      expect(category).not_to be_valid
    end
  end

  describe '#forecast_method_label' do
    it 'reads as the words the reader chose between' do
      expect(category.forecast_method_label).to eq("An average of recent months")
    end
  end

  describe '#manual_forecasts' do
    # Unlike transactions and rules, a hand-entered figure is a prediction *of* this category and means
    # nothing without it, so it goes when the category goes.
    it 'go with the category rather than holding up its deletion' do
      create(:manual_forecast, category: category)

      expect { category.destroy! }.to change(ManualForecast, :count).by(-1)
    end
  end
end
