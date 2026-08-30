# Proposing which counterparties are the same payee, reached from the counterparties list.
#
# Its own controller rather than an action on CounterpartiesController, the same habit as
# CounterpartyMergesController and CsvAnalysesController: the operation is the noun.  All the work is
# MergeSuggester's; this decides what to show and what to say when there is nothing.
#
# GET rather than POST even though it spends money on an API call, because it changes nothing here: it is
# safe to reload, and the reader who wants a second opinion should be able to ask for one.
class MergeSuggestionsController < ApplicationController
  # GET /merge_suggestions
  def index
    suggester = MergeSuggester.new
    @groups = suggester.groups
    @error = suggester.error
  end
end
