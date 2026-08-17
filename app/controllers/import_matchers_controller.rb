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
    @import_matchers = @account.import_matchers.includes(:category, :other_party).order(:description)
    @import_matchers = @import_matchers.where("description LIKE ?", "%#{params[:q]}%") if params[:q].present?

    # How many transactions each rule has actually caught, which is what says whether it earns its keep.
    # One grouped query: an account can carry a few hundred rules.
    @match_counts = @account.transactions.group(:import_matcher_id).count
  end

  # GET /accounts/:account_id/import_matchers/1
  def show
  end

  # GET /accounts/:account_id/import_matchers/new
  def new
    @import_matcher = @account.import_matchers.new
  end

  # GET /accounts/:account_id/import_matchers/1/edit
  def edit
  end

  # POST /accounts/:account_id/import_matchers
  def create
    @import_matcher = @account.import_matchers.new(import_matcher_params)

    respond_to do |format|
      if @import_matcher.save
        format.html do
          redirect_to account_import_matchers_path(@account), notice: "Rule was successfully created."
        end
        format.json { render :show, status: :created, location: [ @account, @import_matcher ] }
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
        format.html do
          redirect_to account_import_matchers_path(@account), notice: "Rule was successfully updated."
        end
        format.json { render :show, status: :ok, location: [ @account, @import_matcher ] }
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
                                      :category_id, :other_party_id ])
    end
end
