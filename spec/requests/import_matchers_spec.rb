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

  describe "GET /accounts/:account_id/import_matchers/new" do
    it "opens an empty form when nothing is handed to it" do
      get new_account_import_matcher_path(account)

      expect(response).to have_http_status(:ok)
    end

    it "prefills the form from a transaction handed to it in the query string" do
      get new_account_import_matcher_path(account, import_matcher: { description: "GITHUB INC.",
                                                                     category_id: utilities.id,
                                                                     counterparty_id: octopus.id })

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="GITHUB INC."')
      expect(response.body).to include(%(<option selected="selected" value="#{utilities.id}">))
      expect(response.body).to include(%(<option selected="selected" value="#{octopus.id}">))
    end

    # nil means "any transaction type", which is nearly always what a rule generalised from one example
    # wants, so the row deliberately does not offer the one it happened to see.
    it "leaves the transaction type blank even where one is handed to it" do
      get new_account_import_matcher_path(account, import_matcher: { description: "GITHUB INC.",
                                                                     trx_type: "DEB" })

      expect(response.body).not_to include('value="DEB"')
    end

    # A literal rule compares the description exactly, spaces included, so a description that really has
    # them has to arrive with them intact or the rule made from it would never fire.
    it "keeps a description's leading and trailing spaces" do
      get new_account_import_matcher_path(account, import_matcher: { description: "  GITHUB INC. " })

      expect(response.body).to include('value="  GITHUB INC. "')
    end

    it "ignores a nonsense import_matcher parameter rather than failing on it" do
      get new_account_import_matcher_path(account, import_matcher: "nonsense")

      expect(response).to have_http_status(:ok)
    end

    it "ignores an account_id in the query string" do
      get new_account_import_matcher_path(account, import_matcher: { account_id: other_account.id })

      expect(response).to have_http_status(:ok)
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

    # The route is nested under :accounts only, so a polymorphic [ account, matcher ] location would look
    # for bank_account_import_matcher_url and raise after the rule had already been saved.
    it "returns the nested URL of the new rule as JSON" do
      post account_import_matchers_path(account, format: :json),
           params: { import_matcher: { description: "TESCO STORES 2889", category_id: utilities.id } }

      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to eq account_import_matcher_url(account, ImportMatcher.last)
    end

    # A rule is written because a transaction went uncategorised, so it has to reach backwards as well as
    # forwards; ImportMatcher.find_match otherwise runs only inside the import.
    it "applies the new rule to transactions already imported, and says how many" do
      rows = Array.new(4) do |month|
        create(:github_subscription, account: account, date: Date.new(2024, 9, 12) + month.months)
      end

      post account_import_matchers_path(account),
           params: { import_matcher: { description: "GITHUB INC.", category_id: utilities.id,
                                       counterparty_id: octopus.id } }

      expect(flash[:notice])
        .to eq "Rule was successfully created. It also categorised 4 transactions already imported."
      expect(rows.map { |row| row.reload.category_id }).to all eq utilities.id
      expect(rows.map { |row| row.reload.import_matcher_id }).to all eq ImportMatcher.last.id
    end

    it "says nothing about existing transactions when it caught none" do
      post account_import_matchers_path(account),
           params: { import_matcher: { description: "GITHUB INC.", category_id: utilities.id } }

      expect(flash[:notice]).to eq "Rule was successfully created."
    end

    it "leaves a transaction somebody categorised by hand out of it" do
      travel = Category.find_by!(name: "Travel")
      by_hand = create(:github_subscription, account: account, date: Date.new(2024, 9, 12), category: travel)
      create(:github_subscription, account: account, date: Date.new(2024, 10, 12))

      post account_import_matchers_path(account),
           params: { import_matcher: { description: "GITHUB INC.", category_id: utilities.id } }

      expect(flash[:notice])
        .to eq "Rule was successfully created. It also categorised 1 transaction already imported."
      expect(by_hand.reload.category_id).to eq travel.id
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

    # The rules screen exists to correct what the analysis import derived, and a description with a typo in
    # it caught nothing at all — fixing it is the moment the reader expects it to start working.
    it "applies a corrected rule to transactions already imported" do
      matcher = create(:import_matcher, account: account, description: "GITHUB INK.", category: utilities)
      row = create(:github_subscription, account: account, date: Date.new(2024, 9, 12))

      patch account_import_matcher_path(account, matcher),
            params: { import_matcher: { description: "GITHUB INC." } }

      expect(flash[:notice])
        .to eq "Rule was successfully updated. It also categorised 1 transaction already imported."
      expect(row.reload.import_matcher_id).to eq matcher.id
    end

    it "returns the nested URL of the rule as JSON" do
      matcher = create(:import_matcher_octopus_energy, account: account)

      patch account_import_matcher_path(account, matcher, format: :json),
            params: { import_matcher: { trx_type: "DEB" } }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Location"]).to eq account_import_matcher_url(account, matcher)
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
