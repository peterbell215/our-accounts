require 'rails_helper'

RSpec.describe "ImportMatchers", type: :request do
  let(:account) { create(:lloyds_account) }
  let(:other_account) { create(:barclay_card_account) }
  let(:utilities) { Category.find_by!(name: "Utilities") }
  let(:octopus) { Counterparty.find_by(name: "Octopus Energy") || create(:octopus_energy) }

  describe "GET /accounts/:account_id/import_matchers" do
    it "lists only this account's rules" do
      mine = create(:import_matcher_octopus_energy, account: account)
      theirs = create(:import_matcher_amazon, account: other_account)

      get account_import_matchers_path(account)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(mine.description)
      expect(response.body).not_to include(theirs.description)
    end

    it "narrows the list by description" do
      octopus_rule = create(:import_matcher_octopus_energy, account: account)
      amazon = create(:import_matcher_amazon, account: account)

      get account_import_matchers_path(account, q: "AMAZ")

      expect(response.body).to include(amazon.description)
      expect(response.body).not_to include(octopus_rule.description)
    end
  end

  describe "POST /accounts/:account_id/import_matchers" do
    it "creates a rule against the account in the route" do
      expect {
        post account_import_matchers_path(account),
             params: { import_matcher: { description: "TESCO STORES 2889", category_id: utilities.id,
                                         counterparty_id: octopus.id, trx_type: "DEB" } }
      }.to change(ImportMatcher, :count).by(1)

      expect(response).to redirect_to(account_import_matchers_path(account))
      expect(ImportMatcher.last.account).to eq account
    end

    it "creates a rule with no counterparty" do
      expect {
        post account_import_matchers_path(account),
             params: { import_matcher: { description: "O2", category_id: utilities.id, counterparty_id: "" } }
      }.to change(ImportMatcher, :count).by(1)

      expect(ImportMatcher.last.counterparty).to be_nil
    end

    # The account is taken from the route, so a body naming another one cannot move the rule.
    it "ignores an account_id in the body" do
      post account_import_matchers_path(account),
           params: { import_matcher: { description: "TESCO", category_id: utilities.id,
                                       account_id: other_account.id } }

      expect(ImportMatcher.last.account).to eq account
    end

    it "re-renders the form when the regex will not compile" do
      expect {
        post account_import_matchers_path(account),
             params: { import_matcher: { description: "TESCO(", description_is_regex: "1",
                                         category_id: utilities.id } }
      }.not_to change(ImportMatcher, :count)

      expect(response).to have_http_status(422)
      expect(response.body).to include("not a valid regular expression")
    end
  end

  describe "PATCH /accounts/:account_id/import_matchers/:id" do
    it "updates the rule" do
      matcher = create(:import_matcher_octopus_energy, account: account)

      patch account_import_matcher_path(account, matcher),
            params: { import_matcher: { trx_type: "" } }

      expect(matcher.reload.trx_type).to be_nil
    end

    it "does not reach a rule belonging to another account" do
      matcher = create(:import_matcher_octopus_energy, account: other_account)

      patch account_import_matcher_path(account, matcher), params: { import_matcher: { trx_type: "X" } }

      expect(response).to have_http_status(:not_found)
      expect(matcher.reload.trx_type).to eq "DD"
    end
  end

  describe "DELETE /accounts/:account_id/import_matchers/:id" do
    it "destroys the rule" do
      matcher = create(:import_matcher_octopus_energy, account: account)

      expect { delete account_import_matcher_path(account, matcher) }
        .to change(ImportMatcher, :count).by(-1)

      expect(response).to redirect_to(account_import_matchers_path(account))
    end
  end
end
