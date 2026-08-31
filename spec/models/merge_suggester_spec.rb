require 'rails_helper'

describe MergeSuggester, type: :model do
  # Nothing here reaches the network.  The client is injected, and the double stands in for the shape the
  # SDK returns: content blocks whose #type is a Symbol, plus stop_reason and stop_details.
  Block = Struct.new(:type, :text)
  Reply = Struct.new(:content, :stop_reason, :stop_details, keyword_init: true)

  def reply_with(groups)
    Reply.new(content: [ Block.new(:text, { groups: groups }.to_json) ], stop_reason: :end_turn)
  end

  # Captures what was sent as well as answering, so a spec can assert on the payload.
  def client_returning(reply)
    messages = double("messages")
    allow(messages).to receive(:create) { |**kwargs| @sent = kwargs; reply }
    double("client", messages: messages)
  end

  def suggester_for(reply, counterparties: Counterparty.order(:name))
    described_class.new(counterparties: counterparties, client: client_returning(reply))
  end

  let!(:tesco_stores) { create(:counterparty, name: "TESCO STORES 2889", account_number: "1") }
  let!(:tesco_2228)   { create(:counterparty, name: "TESCO STORES 2228", account_number: "2") }
  let!(:tesco_pump)   { create(:counterparty, name: "TESCO PAY AT PUMP", account_number: "3") }

  let(:tesco_group) do
    [ { name: "Tesco", members: [ "TESCO STORES 2889", "TESCO STORES 2228" ], reason: "Same shop, truncated." } ]
  end

  describe 'building groups from the answer' do
    it 'returns a group over the counterparties it names' do
      group = suggester_for(reply_with(tesco_group)).groups.sole

      expect(group.name).to eq "Tesco"
      expect(group.counterparties).to contain_exactly(tesco_stores, tesco_2228)
      expect(group.reason).to eq "Same shop, truncated."
    end

    it 'carries the ids the confirmation screen needs' do
      expect(suggester_for(reply_with(tesco_group)).groups.sole.ids)
        .to contain_exactly(tesco_stores.id, tesco_2228.id)
    end

    # A name nothing holds cannot be merged, and sending the reader to a confirmation screen for a record
    # that does not exist is worse than saying nothing.
    it 'drops a name no counterparty has' do
      answer = [ { name: "Tesco", members: [ "TESCO STORES 2889", "TESCO STORES 2228", "SAINSBURYS 44" ],
                   reason: "Same shop." } ]

      expect(suggester_for(reply_with(answer)).groups.sole.counterparties)
        .to contain_exactly(tesco_stores, tesco_2228)
    end

    it 'drops a group left with fewer than two members once unknown names are removed' do
      answer = [ { name: "Sainsburys", members: [ "TESCO STORES 2889", "SAINSBURYS 44" ], reason: "?" } ]

      expect(suggester_for(reply_with(answer)).groups).to be_empty
    end

    it 'drops a repeat of a set it has already proposed' do
      answer = tesco_group + [ { name: "Tesco Stores", members: [ "TESCO STORES 2228", "TESCO STORES 2889" ],
                                 reason: "The same pair again." } ]

      expect(suggester_for(reply_with(answer)).groups.size).to eq 1
    end

    it 'puts the largest group first, that being the most worth doing' do
      answer = tesco_group + [ { name: "All Tesco",
                                 members: [ "TESCO STORES 2889", "TESCO STORES 2228", "TESCO PAY AT PUMP" ],
                                 reason: "One brand." } ]

      expect(suggester_for(reply_with(answer)).groups.first.counterparties.size).to eq 3
    end
  end

  describe 'marking a group whose members disagree about the category' do
    before do
      create(:import_matcher, counterparty: tesco_stores, category: Category.find_by!(name: "Shopping"),
                              description: "TESCO STORES 2889")
      create(:import_matcher, counterparty: tesco_pump, category: Category.find_by!(name: "Travel"),
                              description: "TESCO PAY AT PUMP")
    end

    it 'flags a group spanning two categories' do
      answer = [ { name: "Tesco", members: [ "TESCO STORES 2889", "TESCO PAY AT PUMP" ], reason: "One brand." } ]
      group = suggester_for(reply_with(answer)).groups.sole

      expect(group.categories).to eq [ "Shopping", "Travel" ]
      expect(group).to be_categories_clash
    end

    it 'does not flag a group whose members agree' do
      create(:import_matcher, counterparty: tesco_2228, category: Category.find_by!(name: "Shopping"),
                              description: "TESCO STORES 2228")

      expect(suggester_for(reply_with(tesco_group)).groups.sole).not_to be_categories_clash
    end
  end

  describe 'what is sent' do
    before do
      create(:import_matcher, counterparty: tesco_stores, category: Category.find_by!(name: "Shopping"),
                              description: "TESCO STORES 2889")
      account = BankAccount.find_by(name: "Lloyds Account") || create(:lloyds_account)
      create(:transaction, account: account, counterparty: tesco_stores,
                           date: Date.new(2024, 6, 1), description: "TESCO STORES 2889",
                           amount: Money.from_amount(-43.10))
    end

    it 'sends every counterparty name with the categories its rules assign' do
      suggester_for(reply_with([])).groups
      content = @sent[:messages].first[:content]

      expect(content).to include("TESCO STORES 2889\tShopping")
      expect(content).to include("TESCO PAY AT PUMP")
    end

    # The undertaking the screen makes to the reader, kept as a spec so it cannot quietly stop being true.
    it 'sends no amounts, dates or account numbers' do
      suggester_for(reply_with([])).groups
      content = @sent[:messages].first[:content]

      expect(content).not_to include("43.10", "4310", "2024-06-01")
      expect(content).not_to include(tesco_stores.account_number)
    end

    it 'asks for the answer against its schema, under the SDK spelling of the parameter' do
      suggester_for(reply_with([])).groups

      expect(@sent[:output_config][:format_][:schema]).to eq described_class::SCHEMA
    end
  end

  # Which provider is talked to is configuration rather than code, so these assert on how the client is
  # built rather than reaching inside it. Nothing here reaches the network either: Anthropic::Client.new
  # is stubbed, so no client is ever constructed.
  describe 'choosing a provider from the credentials' do
    let(:reply) { reply_with([]) }

    def with_credentials(settings)
      allow(Rails.application.credentials).to receive(:dig).with(:anthropic).and_return(settings)
    end

    # The environment is controlled rather than read: CLAUDE_CODE_OAUTH_TOKEN is exported on the machines
    # this is developed on, so a spec that left it alone would pass or fail depending on whose shell ran it.
    def with_oauth_token(token)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with(described_class::OAUTH_TOKEN_VARIABLE).and_return(token)
    end

    def stub_client
      messages = double("messages")
      allow(messages).to receive(:create) { |**kwargs| @sent = kwargs; reply }
      client = double("client", messages: messages)
      allow(Anthropic::Client).to receive(:new).and_return(client)
      client
    end

    # The first-party API wants x-api-key, which is what `api_key:` sends, and its own default host.
    it 'sends a key as api_key, with no base_url of its own' do
      with_oauth_token(nil)
      with_credentials(api_key: "sk-ant-test")
      stub_client

      described_class.new.groups

      expect(Anthropic::Client).to have_received(:new).with(api_key: "sk-ant-test")
    end

    # DigitalOcean and other gateways want Authorization: Bearer, which is what `auth_token:` sends.
    it 'sends a token as auth_token, with the base_url it was given' do
      with_oauth_token(nil)
      with_credentials(auth_token: "dop_v1_test", base_url: "https://inference.do-ai.run")
      stub_client

      described_class.new.groups

      expect(Anthropic::Client).to have_received(:new)
        .with(auth_token: "dop_v1_test", base_url: "https://inference.do-ai.run")
    end

    # A token left behind from trying a gateway should not quietly outrank a real key.
    it 'prefers a key over a token where both are set' do
      with_credentials(api_key: "sk-ant-test", auth_token: "dop_v1_test")
      stub_client

      described_class.new.groups

      expect(Anthropic::Client).to have_received(:new).with(api_key: "sk-ant-test")
    end

    # Model ids are provider-specific — the same model is claude-opus-5 first-party and
    # anthropic-claude-opus-5 on DigitalOcean — so it has to travel with the rest of the settings.
    it 'sends the configured model' do
      with_credentials(api_key: "sk-ant-test", model: "anthropic-claude-opus-5")
      stub_client

      described_class.new.groups

      expect(@sent[:model]).to eq "anthropic-claude-opus-5"
    end

    it 'falls back to the default model where none is configured' do
      with_credentials(api_key: "sk-ant-test")
      stub_client

      described_class.new.groups

      expect(@sent[:model]).to eq described_class::MODEL
    end

    # The Claude Code CLI's credential, used in development where no API key is issued. An OAuth token is
    # only accepted alongside anthropic-beta: oauth-2025-04-20, and the SDK attaches that header on exactly
    # one path — a credential *provider* — so a bare auth_token: would be sent without it and refused.
    it 'wraps the Claude Code token in a provider, so the OAuth beta header travels with it' do
      with_credentials(nil)
      with_oauth_token("sk-ant-oat01-test")
      stub_client

      described_class.new.groups

      expect(Anthropic::Client).to have_received(:new) do |**kwargs|
        expect(kwargs.keys).to eq [ :credentials ]
        expect(kwargs[:credentials]).to be_a Anthropic::Credentials::StaticToken
      end
    end

    # Configured credentials are deliberate per-environment configuration; an exported variable is whatever
    # happened to be in the shell. Production settings must not be overridden by a developer's own token.
    it 'prefers a configured credential over the environment' do
      with_credentials(auth_token: "dop_v1_test", base_url: "https://inference.do-ai.run")
      with_oauth_token("sk-ant-oat01-test")
      stub_client

      described_class.new.groups

      expect(Anthropic::Client).to have_received(:new)
        .with(auth_token: "dop_v1_test", base_url: "https://inference.do-ai.run")
    end

    # The state a checkout with neither is in, so it has to read as setup rather than as breakage.
    it 'reports having no credential at all, rather than raising' do
      with_credentials(nil)
      with_oauth_token(nil)
      suggester = described_class.new

      expect(suggester.groups).to be_empty
      expect(suggester.error).to include("No anthropic.api_key or anthropic.auth_token",
                                         described_class::OAUTH_TOKEN_VARIABLE)
    end
  end

  describe 'when there is nothing to ask about' do
    it 'asks nothing at all on a list too short to hold a duplicate' do
      client = client_returning(reply_with([]))
      expect(client.messages).not_to receive(:create)

      expect(described_class.new(counterparties: [ tesco_stores ], client: client).groups).to be_empty
    end
  end

  describe 'when the request does not answer' do
    # A suggestion is a convenience on a screen that works without it, so a failure says so and leaves the
    # list alone rather than turning the counterparties screen into an error page.
    it 'reports a connection failure rather than raising' do
      messages = double("messages")
      allow(messages).to receive(:create).and_raise(Anthropic::Errors::APIConnectionError.new(url: "x"))
      suggester = described_class.new(client: double("client", messages: messages))

      expect(suggester.groups).to be_empty
      expect(suggester.error).to include("Could not reach the API")
    end

    it 'reports a refusal rather than parsing an empty answer' do
      refusal = Reply.new(content: [], stop_reason: :refusal,
                          stop_details: double("details", category: :cyber))
      suggester = suggester_for(refusal)

      expect(suggester.groups).to be_empty
      expect(suggester.error).to include("declined", "cyber")
    end

    it 'reports an answer it cannot read' do
      unreadable = Reply.new(content: [ Block.new(:text, "not json") ], stop_reason: :end_turn)
      suggester = suggester_for(unreadable)

      expect(suggester.groups).to be_empty
      expect(suggester.error).to include("could not be read")
    end
  end
end
