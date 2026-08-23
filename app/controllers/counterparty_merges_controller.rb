# Folding several counterparties into one, driven from the counterparties list.
#
# Its own controller rather than extra actions on CounterpartiesController, the same habit as
# CsvAnalysesController: the operation is the noun.  All the work is CounterpartyMerge's; this decides what
# to show and what to say afterwards.
class CounterpartyMergesController < ApplicationController
  # GET /counterparty_merges/new?ids[]=1&ids[]=2
  #
  # The confirmation.  Reached by a GET form from the list because showing it changes nothing — it should be
  # safe to reload, and the ticked ids belong in the URL where they can be seen.
  def new
    @counterparties = Counterparty.where(id: ids).order(:name)

    if @counterparties.size < CounterpartyMerge::MINIMUM
      return redirect_to counterparties_path,
                         alert: "Tick at least #{CounterpartyMerge::MINIMUM} counterparties to merge them."
    end

    @counts = Transaction.where(counterparty: @counterparties).group(:counterparty_id).count
    @totals = Transaction.where(counterparty: @counterparties).group(:counterparty_id).sum(:amount_pence)
    @categories = categories_by_counterparty
    # params[:name] is what #create redirected back with — the name that was refused, so it can be corrected
    # rather than retyped.  Only a first visit has no name to keep.
    @merge = CounterpartyMerge.new(ids: ids, name: params[:name].presence || suggested_name)
  end

  # POST /counterparty_merges
  def create
    @merge = CounterpartyMerge.new(ids: ids, name: params[:name])

    if @merge.merge
      redirect_to @merge.survivor, notice: merged_notice
    else
      # Straight back to the confirmation with everything still ticked *and the name still as typed*, so a
      # rejected name can be corrected rather than re-selected from scratch.  Carrying the ids without the
      # name would be worse than starting over: the box would silently revert to the suggested name, and
      # submitting again would merge under a name nobody chose.
      redirect_to new_counterparty_merge_path(ids: ids, name: params[:name]), alert: @merge.error
    end
  end

  private

  def ids = Array(params[:ids]).map(&:to_s)

  # Frequencies are named only when any moved, because on most merges none exist and a "0 payment
  # frequencies" clause would be noise on every one.  When some did move it is worth saying: a merge can
  # drop one, where the survivor was already ruled on in the same category, and a ruling that vanished
  # silently is exactly what this notice is for.
  def merged_notice
    moved = [ "#{helpers.pluralize(@merge.transactions_moved, 'transaction')}",
              "#{helpers.pluralize(@merge.matchers_moved, 'rule')}" ]
    moved << "#{helpers.pluralize(@merge.schedules_moved, 'payment frequency')}" if
      @merge.schedules_moved.positive?

    "Merged into #{@merge.survivor.name}: #{moved.to_sentence} moved."
  end

  # The distinct categories each member's rules assign, so the confirmation can show them per row.  That
  # list is the best signal available that a group is not really one payee.
  def categories_by_counterparty
    ImportMatcher.where(counterparty: @counterparties).includes(:category)
                 .group_by(&:counterparty_id)
                 .transform_values { |matchers| matchers.map { |m| m.category.name }.uniq.sort }
  end

  # A starting point for the name, not a decision: the shortest name in the group, which for
  # TESCO STORES 2228 / TESCO STORES 2889 / TESCO STORES is the one closest to what the payee is called.
  # Whatever is offered, the reader is expected to type over it.
  def suggested_name
    @counterparties.map(&:name).min_by(&:length).to_s
  end
end
