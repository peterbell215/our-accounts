require 'rails_helper'

RSpec.describe "Categories", type: :request do
  let(:lloyds) { create(:lloyds_account) }
  let(:utilities) { Category.find_by!(name: "Utilities") }

  describe "PATCH /categories/:id — how the category is forecast" do
    it "records the method chosen" do
      patch category_path(utilities), params: { category: { forecast_method: "regular_payments" } }

      expect(utilities.reload).to be_forecast_regular_payments
      expect(response).to redirect_to(category_path(utilities))
    end

    it "records a lookback of its own" do
      patch category_path(utilities), params: { category: { forecast_months: "12" } }

      expect(utilities.reload.forecast_window).to eq(12)
    end

    # `validate: true` on the enum is what makes this a 422 rather than an ArgumentError out of the setter.
    it "refuses a method it does not have, rather than raising" do
      patch category_path(utilities), params: { category: { forecast_method: "wishful_thinking" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(utilities.reload).to be_forecast_monthly_average
    end

    it "refuses a lookback of no months" do
      patch category_path(utilities), params: { category: { forecast_months: "0" } }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /categories/:id/edit — the payees behind a regular-payments category" do
    let(:data) { ForecastDataBuilder.new(today: Date.current).build }

    it "lists what the forecast found, and whether each is part of it" do
      get edit_category_path(data.subscriptions)

      expect(response.body).to include("payment_frequencies", "Octopus Energy", "South Staffs Water",
                                       "ANCIENT STREAMING CO")
      # The one that has gone quiet says so rather than simply not being there.
      expect(response.body).to include("nothing since")
    end

    it "offers each payee a frequency to set by hand" do
      get edit_category_path(data.subscriptions)

      expect(response.body).to include("Work it out from the history", "Not a regular payment", "Quarterly")
    end

    it "shows a frequency already set as the one in force" do
      create(:payment_schedule, category: data.subscriptions, counterparty: data.energy, cadence_months: 12)

      get edit_category_path(data.subscriptions)

      # The frequency itself is the selected option in the row's dropdown; what reads as prose is that the
      # payee is in the forecast on the reader's word rather than on the history's.
      expect(response.body).to include("at the frequency you set")
    end

    # The section is about payments, so a category predicted any other way has no business showing it.
    # Asserted on the table rather than the heading, because "Its regular payments, one at a time" is one
    # of the choices in the select on every category form.
    it "shows nothing of the sort for a category predicted by an average" do
      get edit_category_path(data.food)

      expect(response.body).not_to include("payment_frequencies")
      expect(response.body).to include("Months to average over")
    end
  end

  describe "GET /categories" do
    it "can be ordered by how each category is forecast" do
      Category.find_by!(name: "Travel").update!(forecast_method: :excluded)

      get categories_path(sort: "forecast_method", direction: "asc")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("An average of recent months", "Not forecast")
    end
  end

  describe "DELETE /categories/:id" do
    it "destroys a category nothing depends on" do
      spare = Category.create!(name: "Spare Category")

      expect { delete category_path(spare) }.to change(Category, :count).by(-1)

      expect(response).to redirect_to(categories_path)
    end

    # import_matchers.category_id carries a foreign key and a rule means nothing without its category, so
    # this used to raise ActiveRecord::InvalidForeignKey — a 500 from a button the Show screen puts up front.
    it "refuses to destroy a category an import rule still assigns, and says which rules" do
      create(:import_matcher, description: "OCTOPUS ENERGY", category: utilities,
                              counterparty: create(:octopus_energy), account: lloyds)

      expect { delete category_path(utilities) }.not_to change(Category, :count)

      expect(response).to redirect_to(category_path(utilities))
      expect(flash[:alert]).to include("Utilities", "OCTOPUS ENERGY", "1 import rule")
    end

    # No foreign key covers transactions.category_id, so before :nullify this left rows pointing at a
    # category that had gone.
    it "keeps transactions filed under it, and stops them naming a category" do
      transaction = create(:tesco_shop, account: lloyds, category: utilities, date: Date.new(2024, 7, 1))

      delete category_path(utilities)

      expect(response).to redirect_to(categories_path)
      expect(transaction.reload).to be_present
      expect(transaction.category_id).to be_nil
    end
  end
end
