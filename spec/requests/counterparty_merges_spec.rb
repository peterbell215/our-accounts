require 'rails_helper'

RSpec.describe "CounterpartyMerges", type: :request do
  let(:lloyds) { create(:lloyds_account) }
  let(:utilities) { Category.find_by!(name: "Utilities") }
  let(:travel) { Category.find_by!(name: "Travel") }

  def counterparty(name, transactions: 1, category: utilities)
    Counterparty.create!(name: name).tap do |cp|
      create(:import_matcher, description: name, category: category, counterparty: cp, account: lloyds)
      transactions.times do |i|
        create(:tesco_shop, account: lloyds, counterparty: cp, date: Date.new(2024, 7, 1) + i)
      end
    end
  end

  describe "GET /counterparty_merges/new" do
    let!(:first) { counterparty("TESCO STORES 2228", transactions: 3) }
    let!(:second) { counterparty("TESCO STORES 2889", transactions: 2) }

    it "lists what is about to be folded together, with counts and totals" do
      get new_counterparty_merge_path(ids: [ first.id, second.id ])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("TESCO STORES 2228", "TESCO STORES 2889")
      expect(response.body).to include("Utilities")
    end

    it "says plainly that categories are unchanged" do
      get new_counterparty_merge_path(ids: [ first.id, second.id ])

      expect(response.body).to include("no category changes")
    end

    it "offers the shortest name as a starting point" do
      third = counterparty("TESCO STORES")

      get new_counterparty_merge_path(ids: [ first.id, second.id, third.id ])

      expect(response.body).to include('value="TESCO STORES"')
    end

    it "warns when the rules disagree about the category" do
      petrol = counterparty("TESCO PAY AT PUMP", category: travel)

      get new_counterparty_merge_path(ids: [ first.id, petrol.id ])

      expect(response.body).to include("do not agree on a category")
      expect(response.body).to include("Travel and Utilities")
    end

    it "does not warn when they agree" do
      get new_counterparty_merge_path(ids: [ first.id, second.id ])

      expect(response.body).not_to include("do not agree on a category")
    end

    it "sends a single selection back to the list rather than showing a pointless form" do
      get new_counterparty_merge_path(ids: [ first.id ])

      expect(response).to redirect_to(counterparties_path)
      expect(flash[:alert]).to match(/at least 2/)
    end

    it "ignores an id belonging to one of the household's own accounts" do
      get new_counterparty_merge_path(ids: [ first.id, second.id, lloyds.id ])

      expect(response.body).not_to include("Lloyds Account")
    end
  end

  describe "POST /counterparty_merges" do
    let!(:first) { counterparty("WAITROSE 651", transactions: 3) }
    let!(:second) { counterparty("WAITROSE 108", transactions: 2) }

    it "merges and lands on the survivor" do
      post counterparty_merges_path, params: { ids: [ first.id, second.id ], name: "Waitrose" }

      expect(response).to redirect_to(counterparty_path(first))
      expect(first.reload.name).to eq "Waitrose"
      expect(first.counterparty_transactions.count).to eq 5
    end

    it "reports what moved" do
      post counterparty_merges_path, params: { ids: [ first.id, second.id ], name: "Waitrose" }

      expect(flash[:notice]).to eq "Merged into Waitrose: 2 transactions and 1 rule moved."
    end

    it "takes a name none of them had" do
      post counterparty_merges_path, params: { ids: [ first.id, second.id ], name: "ATM" }

      expect(first.reload.name).to eq "ATM"
    end

    # Both halves matter: without the ids the selection is lost, and without the name the box silently
    # reverts to the suggested name, so submitting again would merge under a name nobody chose.
    it "goes back to the confirmation with the selection and the typed name intact when the name is refused" do
      held = counterparty("Waitrose")

      post counterparty_merges_path, params: { ids: [ first.id, second.id ], name: "Waitrose" }

      expect(response).to redirect_to(
        new_counterparty_merge_path(ids: [ first.id.to_s, second.id.to_s ], name: "Waitrose")
      )
      expect(flash[:alert]).to include("Waitrose")
      expect(held.reload).to be_present
      expect(second.reload).to be_present
    end

    it "offers the refused name back for correction rather than the suggested one" do
      counterparty("Waitrose")

      post counterparty_merges_path, params: { ids: [ first.id, second.id ], name: "Waitrose" }
      follow_redirect!

      expect(response.body).to include('value="Waitrose"')
    end

    it "merges a clashing group anyway, leaving both categories alone" do
      petrol = counterparty("WAITROSE PETROL", category: travel)

      post counterparty_merges_path, params: { ids: [ first.id, petrol.id ], name: "Waitrose" }

      expect(response).to redirect_to(counterparty_path(first))
      expect(first.reload.counterparty_matchers.map { |m| m.category.name })
        .to contain_exactly("Utilities", "Travel")
    end

    it "refuses a lone id" do
      post counterparty_merges_path, params: { ids: [ first.id ], name: "Waitrose" }

      expect(flash[:alert]).to match(/at least 2/)
      expect(first.reload.name).to eq "WAITROSE 651"
    end
  end
end
