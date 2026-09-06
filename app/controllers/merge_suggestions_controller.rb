# Proposing which counterparties are the same payee, reached from the counterparties list.
#
# Its own controller rather than an action on CounterpartiesController, the same habit as
# CounterpartyMergesController and CsvAnalysesController: the operation is the noun.  All the work is
# MergeSuggester's; this decides what to show and what to say when there is nothing.
#
# GET rather than POST even though asking costs an API call, because it changes nothing here: it is safe to
# reload and safe to come back to.
class MergeSuggestionsController < ApplicationController
  # How long a kept answer is worth showing.  Long enough to work through a list of groups one at a time,
  # short enough that a stale one is not still on offer tomorrow.
  KEPT_FOR = 1.hour

  # GET /merge_suggestions
  # GET /merge_suggestions?refresh=1
  #
  # The answer is **kept** rather than recomputed, which is the opposite of what this did at first.  Merging
  # a group sends the reader back here, and asking again on arrival would spend a request to redraw a list
  # that has only lost one row — the merged one, which drops out on its own because its counterparties no
  # longer exist.  Only `refresh` asks again, and only **Suggest again** sets it.
  def index
    @groups = refresh? ? ask : (kept || ask)
    @kept_at = kept_at
  end

  private

  def refresh? = params[:refresh].present?

  # Rails.cache rather than the session: the session is a 4KB cookie and a dozen groups of names and
  # reasons is a substantial fraction of that, with nothing to say what happens on the run that proposes
  # thirty.  Keyed on the signed-in session, so one household member's answer is not served to another —
  # they would see the same suggestions, but "your last run" should mean theirs.
  def cache_key = "merge_suggestions/#{Current.session&.id}"

  def ask
    suggester = MergeSuggester.new
    groups = suggester.groups
    @error = suggester.error

    # A failure is not worth keeping — the next visit should try again rather than re-show the excuse.
    Rails.cache.write(cache_key, { groups: groups, at: Time.current }, expires_in: KEPT_FOR) if @error.nil?

    groups
  end

  # Groups whose counterparties all still exist.  A merged group loses its losers, so it drops out here
  # without another request — which is the whole point of keeping the answer.
  def kept
    held = Rails.cache.read(cache_key)
    return nil if held.nil?

    held[:groups].select { |group| Counterparty.where(id: group.ids).count == group.counterparties.size }
  end

  def kept_at = Rails.cache.read(cache_key)&.fetch(:at, nil)
end
