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
