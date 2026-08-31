# The rules that categorise imported transactions and link them to a counterparty.
#
# A rule belongs to an account, so this is nested under one: the account comes from the route and is never
# a permitted parameter, which is what stops a rule being filed against the wrong account.  Most rules were
# derived wholesale by AnalysisImporter from a hand-analysed statement; these screens are for correcting
# them and adding the ones it could not work out.
class ImportMatchersController < ApplicationController
  before_action :set_account
  before_action :set_import_matcher, only: %i[ show edit update destroy ]

  # GET /accounts/:account_id/import_matchers
  def index
    @import_matchers = @account.import_matchers.includes(:category, :counterparty).order(:description)
    @import_matchers = @import_matchers.where("description LIKE ?", "%#{params[:q]}%") if params[:q].present?

    # How many transactions each rule has actually caught, which is what says whether it earns its keep.
    # One grouped query: an account can carry a few hundred rules.
    @match_counts = @account.transactions.group(:import_matcher_id).count
  end

  # GET /accounts/:account_id/import_matchers/1
  def show
  end

  # GET /accounts/:account_id/import_matchers/new
  #
  # The form can arrive prefilled from a transaction row, so a rule no longer has to have its description
  # retyped.  The prefill is display only — nothing is saved here, and #create re-reads every field from the
  # submitted form — so this is a convenience rather than a second way in.
  def new
    @import_matcher = @account.import_matchers.new(prefill_params)
  end

  # GET /accounts/:account_id/import_matchers/1/edit
  def edit
  end

  # POST /accounts/:account_id/import_matchers
  def create
    @import_matcher = @account.import_matchers.new(import_matcher_params)

    respond_to do |format|
      if @import_matcher.save
        # After the save, not before: applying the rule stamps its id onto the rows it claims.
        applied = RuleApplication.new(matcher: @import_matcher).apply

        format.html do
          redirect_to account_import_matchers_path(@account), notice: notice_for("created", applied)
        end
        format.json { render :show, status: :created, location: account_import_matcher_url(@account, @import_matcher) }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @import_matcher.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /accounts/:account_id/import_matchers/1
  def update
    respond_to do |format|
      if @import_matcher.update(import_matcher_params)
        # A corrected rule should catch what it now matches — a description with a typo in it caught nothing,
        # and fixing the typo is the moment the reader expects it to start working.  Rows the rule already
        # claims are untouched, being neither uncategorised nor unclaimed.
        applied = RuleApplication.new(matcher: @import_matcher).apply

        format.html do
          redirect_to account_import_matchers_path(@account), notice: notice_for("updated", applied)
        end
        format.json { render :show, status: :ok, location: account_import_matcher_url(@account, @import_matcher) }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @import_matcher.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /accounts/:account_id/import_matchers/1
  def destroy
    @import_matcher.destroy!

    respond_to do |format|
      format.html do
        redirect_to account_import_matchers_path(@account), status: :see_other,
                    notice: "Rule was successfully destroyed."
      end
      format.json { head :no_content }
    end
  end

  private
    def set_account
      @account = Account.find(params[:account_id])
    end

    # Found through the association, so a rule belonging to another account is not found at all.
    def set_import_matcher
      @import_matcher = @account.import_matchers.find(params.expect(:id))
    end

    # account_id is deliberately absent: it comes from the route.
    def import_matcher_params
      params.expect(import_matcher: [ :description, :description_is_regex, :trx_type,
                                      :category_id, :counterparty_id, :amount_comparison, :amount ])
    end

    # What a transaction row can hand to the new-rule form.  Three attributes rather than the seven #create
    # permits: trx_type is left blank because nil means "any type", which is what a rule generalised from one
    # example nearly always wants, and description_is_regex unticked because an exact description is the more
    # specific claim and beats a pattern anyway.  account_id is absent for the same reason as above.
    #
    # amount is left out for the same reason as trx_type: prefilling it without also choosing a comparison
    # would hand back an invalid rule (amount present, comparison blank) unless the reader noticed and
    # cleared it, for the common case of a rule meant to match any amount.
    #
    # #permit rather than #expect, and a class check rather than #blank?: expect raises when the key is
    # absent, which is the ordinary case of arriving from "New rule", and a hand-written
    # ?import_matcher=nonsense arrives as a String, which is not blank and does not answer #permit.
    def prefill_params
      prefill = params[:import_matcher]
      return {} unless prefill.is_a?(ActionController::Parameters)

      prefill.permit(:description, :category_id, :counterparty_id)
    end

    # A rule made from a transaction row is nearly always one of several identical transactions, and the
    # count is what says it did its job.  Silent when it caught nothing: "0 transactions" reads as a failure,
    # and a rule written for a description not yet seen legitimately catches none.  Two sentences, so the
    # first is the same on every save.
    # @return [String]
    def notice_for(verb, applied)
      notice = "Rule was successfully #{verb}."
      return notice if applied.zero?

      "#{notice} It also categorised #{helpers.pluralize(applied, 'transaction')} already imported."
    end
end
