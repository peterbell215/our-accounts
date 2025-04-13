require 'rails_helper'

RSpec.describe "Accounts", type: :request do
  describe "PATCH /accounts" do
    it "a PATCH for a BankAccount that is trying to change the type to CreditCard" do
      account = create(:lloyds_account)

      patch account_path(account), params: { account: { name: "Updated Name", type: "CreditCardAccount" } }
      expect(response).to have_http_status(400)
    end

    it "a PATCH for a BankAccount that is trying to change the type to CreditCard" do
      account = create(:barclay_card_account)

      patch account_path(account), params: { account: { name: "Updated Name", type: "BankAccount" } }
      expect(response).to have_http_status(400)
    end
  end
end
