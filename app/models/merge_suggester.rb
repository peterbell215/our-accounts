# Proposes which counterparties are really one payee, so the duplicates do not have to be found by eye.
#
# AnalysisImporter derives one counterparty per distinct statement description, and the bank truncates and
# numbers those, so a single payee arrives many times over.  Four string heuristics were measured against
# the real names before this existed and only one — stripping digits and punctuation — avoided false
# groups: first-word grouping filed twelve unrelated pubs and charities under THE, and treated LNK, SQ *
# and PAYPAL as payees when they are payment rails.  What separates TESCO STORES from TESCO PAY AT PUMP is
# not their spelling, so this asks a model what the words mean instead.
#
# It proposes only.  Every group is a link into the existing confirmation screen, and CounterpartyMerge —
# which is where the load-bearing ordering lives — does the work unchanged, on a set the reader has
# approved.  Nothing here merges anything.
class MergeSuggester
  # The default, used unless the credentials name another.  Model ids are provider-specific: the
  # first-party API calls this `claude-opus-5`, DigitalOcean calls the same model
  # `anthropic-claude-opus-5`, and sending one provider's id to the other is a 404 rather than a
  # helpful message.
  MODEL = :"claude-opus-5"

  # Groups of a few names each, out of a few hundred in: the reply is short, and a cap this size only
  # binds if something has gone wrong.
  MAX_TOKENS = 8_000

  # Below this there is nothing to look for, and asking would cost a request to be told so.
  MINIMUM_COUNTERPARTIES = 3

  SYSTEM = <<~PROMPT.freeze
    You are given the payee names from one household's bank and credit-card statements, each with the
    spending categories that household files it under. The names are raw statement text: the bank
    truncates them to about eighteen characters and appends branch or terminal numbers, so one real payee
    often appears several times under slightly different names.

    Identify sets of names that are the same payee and could be merged into one.

    What counts as the same payee:

    - Truncations and numbered variants of one business — TESCO STORES 2228, TESCO STORES 2889.
    - The same business spelled differently by different systems — NETFLIX.COM and Netflix.

    What does not, however similar the text looks:

    - A payment rail is not a payee. LNK is a cash machine network, SQ * is Square, PAYPAL * is PayPal.
      LNK TESCO is a cash withdrawal at a machine that happens to stand in a Tesco, and it is not the
      supermarket. Never group by the rail.
    - A shared first word is not a payee. THE ROYAL OAK and THE RED LION are two different pubs.
    - The same brand doing different things is not one payee where the household files it differently.
      TESCO STORES under Food and TESCO PAY AT PUMP under Car are the supermarket and the petrol station.
      Treat a category disagreement as strong evidence against a group.

    Prefer proposing nothing to proposing a group you are unsure of. A false group costs the household a
    merge they have to unpick by hand; a missed one costs nothing but the duplicate they already have.
    Returning an empty list is a good answer when the names are already distinct.

    For each group give the name the merged payee should take — the clearest form of the real name, not
    necessarily one of the strings given — and one short sentence saying why they are the same payee.
  PROMPT

  SCHEMA = {
    type: "object",
    properties: {
      groups: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            members: { type: "array", items: { type: "string" } },
            reason: { type: "string" }
          },
          required: [ "name", "members", "reason" ],
          additionalProperties: false
        }
      }
    },
    required: [ "groups" ],
    additionalProperties: false
  }.freeze

  # One proposed merge.  `counterparties` are records, not names: a name the model returned that nothing
  # holds is dropped rather than shown, so a group can only ever point at rows that exist.
  Group = Struct.new(:name, :counterparties, :reason, :categories, keyword_init: true) do
    def ids = counterparties.map(&:id)

    # The same signal CounterpartyMerge#categories_clash? uses on the confirmation screen, carried here so a
    # doubtful group is marked before the reader opens it.
    def categories_clash? = categories.size > 1
  end

  attr_reader :error

  # @param [ActiveRecord::Relation, Array<Counterparty>] counterparties
  # @param [Anthropic::Client, nil] client injected by the specs, which must never reach the network
  def initialize(counterparties: Counterparty.order(:name), client: nil)
    @counterparties = counterparties.to_a
    @client = client
  end

  # @return [Array<Group>] the groups worth showing, largest first; empty where there is nothing to
  #   propose, and also where the request failed — #error says which
  def groups
    @groups ||= begin
      @error = nil
      return [] if @counterparties.size < MINIMUM_COUNTERPARTIES

      build_groups(request_groups)
    rescue Anthropic::Errors::APIError, KeyError => e
      # A suggestion is a convenience on a screen that works without it, so every failure here says so and
      # leaves the list alone rather than turning the counterparties screen into an error page.  KeyError
      # is the commonest of them by far: no key configured, which is the state every checkout starts in.
      @error = failure_message(e)
      []
    end
  end

  private

  # Which provider to talk to is configuration, not code.  One gem reaches both the first-party API and
  # any gateway speaking the Messages API — DigitalOcean's among them — and the whole difference is an
  # auth header, a base URL and a model id, so all three are read rather than compiled in.
  def client
    @client ||= Anthropic::Client.new(**credential, **base_url)
  end

  # `api_key:` sends `x-api-key`, which the first-party API wants; `auth_token:` sends
  # `Authorization: Bearer`, which is what DigitalOcean and other gateways want.  A key wins over a token
  # where both are set: a token left behind from trying a gateway should not quietly outrank a real one.
  def credential
    settings = provider_settings

    if settings[:api_key].present?
      { api_key: settings[:api_key] }
    elsif settings[:auth_token].present?
      { auth_token: settings[:auth_token] }
    else
      raise KeyError, "No anthropic.api_key or anthropic.auth_token in the credentials. " \
                      "Add one with bin/rails credentials:edit."
    end
  end

  # Omitted entirely when unset, so the gem's own default stands rather than being overwritten with nil.
  def base_url
    url = provider_settings[:base_url]
    url.present? ? { base_url: url } : {}
  end

  def model = provider_settings[:model].presence || MODEL

  # Beside seed_data rather than in the environment, so that a checkout with config/master.key needs
  # nothing else set to work.
  def provider_settings
    @provider_settings ||= Rails.application.credentials.dig(:anthropic) || {}
  end

  def request_groups
    message = client.messages.create(
      model: model,
      max_tokens: MAX_TOKENS,
      system_: SYSTEM,
      messages: [ { role: "user", content: payload } ],
      # `format_`, not `format`: Anthropic::OutputConfig declares the attribute with a trailing underscore
      # and `api_name: :format`, the same convention as `system_`. Passing `format:` silently sends no
      # schema at all, and the reply is then ordinary prose that JSON.parse chokes on.
      output_config: { format_: { type: :json_schema, schema: SCHEMA } }
    )

    # A refusal is not an exception: it arrives as a 200 with no answer in it, so it has to be checked
    # before the content is read or the parse fails on an empty string.
    return [] if refused?(message)

    JSON.parse(first_text(message)).fetch("groups", [])
  rescue JSON::ParserError => e
    @error = "The suggestion could not be read: #{e.message}"
    []
  end

  def refused?(message)
    return false unless message.stop_reason == :refusal

    @error = "The request was declined#{" (#{message.stop_details.category})" if message.stop_details}."
    true
  end

  # output_config.format guarantees the first text block is valid JSON against SCHEMA.
  def first_text(message)
    message.content.find { |block| block.type == :text }&.text.to_s
  end

  # One line per counterparty: the name as the statement wrote it, then the categories its rules assign.
  # Names only and categories only — no amounts, no dates, no account numbers, nothing per-transaction.
  # A counterparty with no rule yet contributes its name alone, which is common and not worth a placeholder.
  def payload
    lines = @counterparties.map do |counterparty|
      categories = categories_by_id[counterparty.id]
      categories.present? ? "#{counterparty.name}\t#{categories.join(', ')}" : counterparty.name
    end

    "Payee name\tCategories it is filed under\n#{lines.join("\n")}"
  end

  # Turns the model's answer into groups over records this household actually has.  Three things are
  # dropped rather than shown, all of them silently, because each would send the reader to a confirmation
  # screen that cannot work: a name nothing holds, a group left with fewer than two members once those are
  # dropped, and a repeat of a set already proposed.
  def build_groups(raw)
    by_name = @counterparties.index_by { |c| c.name.downcase }
    seen = Set.new

    raw.filter_map do |group|
      members = Array(group["members"]).filter_map { |name| by_name[name.to_s.downcase] }.uniq
      next if members.size < CounterpartyMerge::MINIMUM
      next unless seen.add?(members.map(&:id).sort)

      Group.new(name: group["name"].to_s.squish, counterparties: members.sort_by(&:name),
                reason: group["reason"].to_s.squish,
                categories: members.flat_map { |m| categories_by_id[m.id].to_a }.uniq.sort)
    end.sort_by { |group| -group.counterparties.size }
  end

  # One query for every counterparty's categories rather than one per counterparty: this runs over a few
  # hundred names, and the same map serves both the payload and the clash marking.
  def categories_by_id
    @categories_by_id ||= ImportMatcher.where(counterparty: @counterparties).includes(:category)
                                       .group_by(&:counterparty_id)
                                       .transform_values { |ms| ms.map { |m| m.category.name }.uniq.sort }
  end

  def failure_message(error)
    case error
    when KeyError
      "No API key is configured, so there is nothing to ask. #{error.message}"
    when Anthropic::Errors::APIConnectionError
      "Could not reach the API. Nothing has changed."
    else
      "The API refused the request: #{error.message}"
    end
  end
end
