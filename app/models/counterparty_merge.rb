# Folds several counterparties into one, under a name the caller chooses.
#
# AnalysisImporter derives one counterparty per distinct statement description, and the bank truncates those
# descriptions to eighteen characters, so a single payee arrives many times over: TESCO STORES 2228, 2555,
# 2889.  Nothing can repair that at source, so it is repaired here, by hand, a group at a time.
#
# What counts as one payee is the caller's judgement, not something this class infers.  Sharing a prefix
# proves nothing — LNK TESCO is a cash machine that happens to stand in a Tesco, and PAYPAL * says only how
# the money travelled — so the set is always chosen deliberately.
#
# Categories are never touched.  Each rule keeps its own description and category, which is what lets one
# counterparty legitimately span several: petrol from Tesco stays Car while the groceries stay Food.
class CounterpartyMerge
  MINIMUM = 2

  # Mirrors Account's own length validation, so a name too short or too long is refused before anything has
  # been moved rather than at the rename, which happens last.
  NAME_RANGE = (3..50).freeze

  attr_reader :counterparties, :name, :survivor, :transactions_moved, :matchers_moved, :schedules_moved,
              :error

  # @param [Array<Integer>, Array<String>] ids the counterparties to fold together
  # @param [String] name what the survivor should be called afterwards; may be a name nothing yet holds
  def initialize(ids:, name:)
    # Counterparty rather than Account, deliberately.  Transaction#counterparty and ImportMatcher#counterparty
    # are both declared class_name: "Account", and nothing in the schema stops one of the household's own
    # accounts being named as a counterparty — so a hand-edited form could otherwise merge away the account
    # holding every transaction.
    @counterparties = Counterparty.where(id: ids).order(:id).to_a
    @name = name.to_s.squish
    @transactions_moved = 0
    @matchers_moved = 0
    @schedules_moved = 0
  end

  # @return [Boolean] whether the merge was carried out
  def merge
    return false unless valid?

    ActiveRecord::Base.transaction do
      @survivor = counterparties.first
      losers = counterparties - [ survivor ]

      # Order matters twice over here, and both mistakes are silent.
      #
      # Re-point before destroying: Account#counterparty_transactions and #counterparty_matchers are
      # dependent: :nullify, so destroying a loser first would null the very rows being moved.
      @transactions_moved = repoint(Transaction, losers)
      @matchers_moved = repoint(ImportMatcher, losers)
      @schedules_moved = move_schedules(losers)

      losers.each(&:destroy!)

      # Rename after destroying: the wanted name is often held by a member of the set — Spotify is held by
      # SPOTIFY, which is being folded in — and Account validates name uniqueness case-insensitively across
      # the whole table, so renaming first would fail against a record about to disappear.
      rename_survivor
    end

    forget_counts if error
    error.nil?
  end

  # @return [Array<String>] the distinct categories the members' rules assign, which is the best signal
  #   available that a group is not really one payee: Food and Car together usually means two payees.
  def rule_categories
    @rule_categories ||= ImportMatcher.where(counterparty: counterparties)
                                      .includes(:category).map { |matcher| matcher.category.name }.uniq.sort
  end

  # @return [Boolean] whether the members' rules disagree about the category
  def categories_clash? = rule_categories.size > 1

  private

  def valid?
    @error =
      if counterparties.size < MINIMUM
        "Select at least #{MINIMUM} counterparties to merge."
      elsif name.blank?
        "Give the merged counterparty a name."
      elsif !NAME_RANGE.cover?(name.length)
        "The name must be between #{NAME_RANGE.min} and #{NAME_RANGE.max} characters."
      elsif (held = held_elsewhere)
        # Naming the survivor after something outside the set cannot work, and saying which record holds the
        # name is the difference between a dead end and an obvious next move: include it in the merge.
        "#{name.inspect} is already held by #{held.name.inspect}. Include it in the merge, or choose another name."
      end

    @error.nil?
  end

  # A counterparty holding the wanted name that is *not* being folded in.  One inside the set is fine — it
  # is about to be destroyed, or it is the survivor being renamed to what it already is.
  #
  # Counterparty rather than Account, to match how #initialize resolves the ids.  Over Account this advised
  # the impossible: naming a merge "Lloyds Account" said to include that account in the merge, when a
  # BankAccount id is filtered out of the set by design.  A name held by one of the household's own accounts
  # is still refused — Account validates uniqueness case-insensitively across the whole table, so
  # #rename_survivor fails and reports it — just without the misleading instruction.
  def held_elsewhere
    Counterparty.named(name).where.not(id: counterparties.map(&:id)).first
  end

  # update_all rather than each(&:update!): one statement per table, and neither model has a callback that
  # needs to run for a re-pointing.  It skips import_matchers.updated_at, which is the intended trade —
  # moving a rule's counterparty is not a change to the rule the reader made.
  #
  # @return [Integer] how many rows moved
  def repoint(model, losers)
    model.where(counterparty: losers).update_all(counterparty_id: survivor.id)
  end

  # Frequencies set by hand travel with the payee, because this is the very moment they are most wanted:
  # a series split across two counterparties is not recognised at all, merging them is the repair, and
  # losing the cadence in the process would undo half of it.
  #
  # Not through #repoint, though the intent is the same.  payment_schedules is uniquely indexed on
  # (category_id, counterparty_id), so a blanket update_all would collide wherever the survivor has
  # already been ruled on in the same category.  The survivor's own ruling wins there — it is the one the
  # reader set against the name they are keeping — and the loser's is dropped rather than merged, since
  # two cadences for one payee cannot both be right and nothing here can tell which.
  def move_schedules(losers)
    schedules = PaymentSchedule.where(counterparty: losers)
    survivor_categories = PaymentSchedule.where(counterparty: survivor).pluck(:category_id)

    schedules.where(category_id: survivor_categories).delete_all
    schedules.where.not(category_id: survivor_categories).update_all(counterparty_id: survivor.id)
  end

  def rename_survivor
    survivor.update!(name: name)
  rescue ActiveRecord::RecordInvalid => e
    @error = e.record.errors.full_messages.to_sentence
    raise ActiveRecord::Rollback
  end

  # The transaction has been rolled back, so nothing moved after all; saying otherwise would have the caller
  # report a merge that did not happen.
  def forget_counts
    @transactions_moved = 0
    @matchers_moved = 0
    @schedules_moved = 0
    @survivor = @survivor&.reload
  end
end
