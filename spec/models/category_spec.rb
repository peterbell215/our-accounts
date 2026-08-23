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

  describe '#counterparty_spend' do
    let(:lloyds) { create(:lloyds_account) }
    let(:barclaycard) { create(:barclay_card_account) }

    # Named so that alphabetical order and spend order disagree, as in the counterparties list specs.
    let(:anvil) { create(:counterparty, name: 'Anvil Works') }
    let(:zebra) { create(:counterparty, name: 'Zebra Supplies') }

    it 'rolls a category up by counterparty, counting the transactions and totalling them' do
      create(:tesco_shop, account: lloyds, category: category, counterparty: anvil,
                          date: Date.new(2024, 7, 1), amount: Money.from_amount(-10.00))
      create(:tesco_shop, account: lloyds, category: category, counterparty: anvil,
                          date: Date.new(2024, 7, 2), amount: Money.from_amount(-5.50))

      expect(category.counterparty_spend).to eq([ [ anvil, 2, Money.from_amount(-15.50) ] ])
    end

    # The whole point of doing this per category rather than reusing the counterparties list: one payee
    # can appear under several categories, and each should only be totalled under its own.
    it 'counts only the transactions filed under this category' do
      other = create(:food_category)

      create(:tesco_shop, account: lloyds, category: category, counterparty: anvil,
                          date: Date.new(2024, 7, 1), amount: Money.from_amount(-10.00))
      create(:tesco_shop, account: lloyds, category: other, counterparty: anvil,
                          date: Date.new(2024, 7, 2), amount: Money.from_amount(-99.00))

      expect(category.counterparty_spend).to eq([ [ anvil, 1, Money.from_amount(-10.00) ] ])
    end

    # A one-off purchase, or a description too cryptic to identify, has no counterparty.  That is expected,
    # so it is left out rather than gathered into a row of its own.
    it 'leaves out the transactions naming nobody' do
      create(:tesco_shop, account: lloyds, category: category, counterparty: nil,
                          date: Date.new(2024, 7, 1), amount: Money.from_amount(-10.00))

      expect(category.counterparty_spend).to be_empty
    end

    # Modelling a counterparty as an account is what makes this cross-account roll-up an ordinary query.
    it 'gathers the spend from every account' do
      create(:tesco_shop, account: lloyds, category: category, counterparty: anvil,
                          date: Date.new(2024, 7, 1), amount: Money.from_amount(-10.00))
      create(:tesco_shop, account: barclaycard, category: category, counterparty: anvil,
                          date: Date.new(2024, 7, 2), amount: Money.from_amount(-4.00))

      expect(category.counterparty_spend).to eq([ [ anvil, 2, Money.from_amount(-14.00) ] ])
    end

    # Spending is negative, so ascending by total is what puts the largest spend at the top.
    it 'puts the counterparty most is spent with first' do
      create(:tesco_shop, account: lloyds, category: category, counterparty: anvil,
                          date: Date.new(2024, 7, 1), amount: Money.from_amount(-5.00))
      create(:tesco_shop, account: lloyds, category: category, counterparty: zebra,
                          date: Date.new(2024, 7, 2), amount: Money.from_amount(-500.00))

      expect(category.counterparty_spend.map(&:first)).to eq([ zebra, anvil ])
    end

    it 'breaks a tie on name, so equal spends still read in a stable order' do
      create(:tesco_shop, account: lloyds, category: category, counterparty: zebra,
                          date: Date.new(2024, 7, 1), amount: Money.from_amount(-5.00))
      create(:tesco_shop, account: lloyds, category: category, counterparty: anvil,
                          date: Date.new(2024, 7, 2), amount: Money.from_amount(-5.00))

      expect(category.counterparty_spend.map(&:first)).to eq([ anvil, zebra ])
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
