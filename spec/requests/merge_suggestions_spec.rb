require 'rails_helper'

RSpec.describe "Merge suggestions", type: :request do
  describe "GET /merge_suggestions" do
    let!(:tesco_stores) { create(:counterparty, name: "TESCO STORES 2889", account_number: "1") }
    let!(:tesco_2228)   { create(:counterparty, name: "TESCO STORES 2228", account_number: "2") }
    let!(:tesco_pump)   { create(:counterparty, name: "TESCO PAY AT PUMP", account_number: "3") }

    # MergeSuggester is stubbed rather than allowed to build its own client: a request spec must not reach
    # the network, and without a key in the test credentials it would not get there anyway.
    def stub_suggester(groups: [], error: nil)
      allow(MergeSuggester).to receive(:new)
        .and_return(instance_double(MergeSuggester, groups: groups, error: error))
    end

    def group(name:, counterparties:, reason: "Same shop.", categories: [ "Shopping" ])
      MergeSuggester::Group.new(name: name, counterparties: counterparties, reason: reason,
                                categories: categories)
    end

    it "lists a suggested group and what it would fold together" do
      stub_suggester(groups: [ group(name: "Tesco", counterparties: [ tesco_stores, tesco_2228 ]) ])

      get merge_suggestions_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Tesco", "TESCO STORES 2889", "TESCO STORES 2228", "Same shop.")
    end

    # The whole point of the screen: it proposes, and the existing confirmation does the work on a set the
    # reader has approved. The link has to carry both ids and the name, or the review starts from scratch.
    it "links each group into the merge confirmation, carrying its ids and name" do
      stub_suggester(groups: [ group(name: "Tesco", counterparties: [ tesco_stores, tesco_2228 ]) ])

      get merge_suggestions_path

      expect(response.body).to include(
        CGI.escapeHTML(new_counterparty_merge_path(ids: [ tesco_stores.id, tesco_2228.id ], name: "Tesco"))
      )
    end

    it "marks a group whose members are filed under more than one category" do
      stub_suggester(groups: [ group(name: "Tesco", counterparties: [ tesco_stores, tesco_pump ],
                                     categories: [ "Shopping", "Travel" ]) ])

      get merge_suggestions_path

      expect(response.body).to include("row-question")
    end

    it "says so when there is nothing to suggest" do
      stub_suggester

      get merge_suggestions_path

      expect(response.body).to include("Nothing to suggest")
    end

    # No key configured is the state every checkout starts in, so it has to read as a thing to set up
    # rather than as a broken screen.
    it "reports a failure without taking the screen down" do
      stub_suggester(error: "No API key is configured, so there is nothing to ask.")

      get merge_suggestions_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No API key is configured")
    end

    it "is reachable from the counterparties list" do
      get counterparties_path

      expect(response.body).to include(merge_suggestions_path)
    end
  end
end
