require 'rails_helper'

RSpec.describe "TradingAccounts", type: :request do
  describe "GET /trading_accounts" do
    it "lists counterparties with what has been spent through them" do
      octopus = create(:octopus_energy_account)
      lloyds = create(:lloyds_account)
      create(:tesco_shop, account: lloyds, other_party: octopus, date: Date.new(2024, 7, 1))

      get trading_accounts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Octopus Energy")
      # money-rails puts the sign inside the symbol, as it does everywhere else in the app.
      expect(response.body).to include("£-5.95")
    end

    it "does not list the household's own accounts" do
      create(:lloyds_account)

      get trading_accounts_path

      expect(response.body).not_to include("Lloyds Account")
    end
  end

  describe "GET /trading_accounts/:id" do
    it "shows that vendor's transactions from every account" do
      octopus = create(:octopus_energy_account)
      create(:tesco_shop, account: create(:lloyds_account), other_party: octopus,
                          date: Date.new(2024, 7, 1), description: "PAID FROM CURRENT")
      create(:tesco_shop, account: create(:barclay_card_account), other_party: octopus,
                          date: Date.new(2024, 7, 2), description: "PAID FROM CARD")

      get trading_account_path(octopus)

      expect(response.body).to include("PAID FROM CURRENT")
      expect(response.body).to include("PAID FROM CARD")
      expect(response.body).to include("Lloyds Account")
      expect(response.body).to include("Barclaycard")
    end
  end

  describe "POST /trading_accounts" do
    it "creates a counterparty" do
      expect { post trading_accounts_path, params: { trading_account: { name: "Thames Water" } } }
        .to change(TradingAccount, :count).by(1)

      expect(TradingAccount.last.name).to eq "Thames Water"
    end

    # Account#name is unique across the whole STI table, so this is a real collision the form has to explain.
    it "refuses a name one of the household's accounts already has" do
      create(:lloyds_account)

      expect { post trading_accounts_path, params: { trading_account: { name: "Lloyds Account" } } }
        .not_to change(TradingAccount, :count)

      expect(response).to have_http_status(422)
      expect(response.body).to include("has already been taken")
    end
  end

  describe "PATCH /trading_accounts/:id" do
    # The point of these screens: the analysis import names counterparties after raw statement text.
    it "renames a counterparty derived from statement text" do
      counterparty = create(:trading_account, name: "TESCO STORES 2889")

      patch trading_account_path(counterparty), params: { trading_account: { name: "Tesco" } }

      expect(counterparty.reload.name).to eq "Tesco"
    end
  end

  describe "DELETE /trading_accounts/:id" do
    it "keeps the transactions that named it" do
      octopus = create(:octopus_energy_account)
      transaction = create(:tesco_shop, account: create(:lloyds_account), other_party: octopus,
                                        date: Date.new(2024, 7, 1))

      expect { delete trading_account_path(octopus) }.to change(TradingAccount, :count).by(-1)

      expect(response).to redirect_to(trading_accounts_path)
      expect(transaction.reload.other_party).to be_nil
    end
  end
end
