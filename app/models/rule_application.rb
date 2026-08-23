# Applies one rule to transactions already in the database.
#
# ImportMatcher.find_match is called from exactly one place in the pipeline — FileImporter, as each row is
# read — so until now a rule written by hand only ever affected the next import.  That is backwards: the
# rules screens exist because the derived rules missed things, and what the reader is looking at when they
# notice is a transaction that has already been imported.  GITHUB INC. arrives monthly, and four of them sat
# uncategorised.  FileImporter categorises forwards; this categorises backwards.
#
# Invoked from ImportMatchersController rather than from a callback on ImportMatcher.  AnalysisImporter
# creates a few hundred rules in one run, against an account whose statements are already imported, so a
# callback would turn one rake task into a few hundred silent sweeps of the transactions table and quietly
# change what re-seeding means.
class RuleApplication
  attr_reader :matcher, :transactions

  # @param [ImportMatcher] matcher the rule to apply
  def initialize(matcher:)
    @matcher = matcher
    @transactions = []
  end

  # @return [Integer] how many transactions the rule claimed
  def apply
    @transactions = candidates.select { |transaction| matcher.match(transaction) }
    return 0 if transactions.empty?

    # update_all rather than each(&:update!), for the reason CounterpartyMerge#repoint gives: one statement,
    # and no callback on Transaction needs to run to re-point three foreign keys.  Both counterparty-name
    # hooks are inert on a record loaded from the database — nothing has been typed — but leaving them out
    # altogether is what stops a validation added to Transaction later turning a half-done application into
    # a silent one.  #sequence must emphatically not run: day_index and balance are already correct, and
    # re-deriving a balance against itself would raise ImportError.  updated_at is left alone as it is
    # there; a rule claiming a row is not an edit the reader made to that transaction.
    Transaction.where(id: transactions.map(&:id)).update_all(updates)
  end

  private

  # @return [Hash]
  def updates
    { category_id: matcher.category_id, import_matcher_id: matcher.id }.tap do |columns|
      # A rule naming no counterparty leaves whatever the row already has.  Transaction#find_match assigns
      # the rule's counterparty unconditionally, which is safe at import time because the row has none to
      # lose; applied backwards it is not — the counterparty may have just been created from this very row.
      columns[:counterparty_id] = matcher.counterparty_id if matcher.counterparty_id
    end
  end

  # Only rows no rule has matched and no hand has categorised.  Both nils are the whole of "hand judgement
  # wins", the principle AnalysisCategoriser is built on: category_id nil means nobody chose, and
  # import_matcher_id nil means no rule got there first on match order.  Overriding either from here would
  # silently reverse a decision somebody made deliberately.
  #
  # A literal description is an equality the database can answer, and the column collates BINARY, which is
  # what Ruby's #== means too — so pushing it down narrows without changing the answer.  A pattern has to be
  # compared in Ruby, SQLite having no REGEXP.  #match is asked in both cases regardless, so it stays the
  # single authority on what a rule matches and the two paths cannot come to disagree.
  # @return [ActiveRecord::Relation]
  def candidates
    scope = matcher.account.transactions.where(category_id: nil, import_matcher_id: nil)
    scope = scope.where(description: matcher.description) unless matcher.description_is_regex?
    scope = scope.where(trx_type: matcher.trx_type) if matcher.trx_type
    scope
  end
end
