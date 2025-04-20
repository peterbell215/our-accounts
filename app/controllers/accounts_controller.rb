class AccountsController < ApplicationController
  before_action :set_account, only: %i[ show edit update destroy ]

  # GET /accounts or /accounts.json
  def index
    @accounts = Account.where("type IN ('BankAccount', 'CreditCardAccount')").order(:name)
  end

  # GET /accounts/1 or /accounts/1.json
  def show
    @categories = Category.order(:name).all
  end

  # GET /accounts/new
  def new
    @account = Account.new
  end

  # GET /accounts/1/edit
  def edit
  end

  # POST /accounts or /accounts.json
  def create
    @account = Account.new(new_account_params)

    respond_to do |format|
      if @account.save
        format.html { redirect_to account_path(@account), notice: "Account was successfully created." }
        format.json { render :show, status: :created, location: @account }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @account.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /accounts/1 or /accounts/1.json
  def update
    respond_to do |format|
      if @account.update(account_params)
        format.html { redirect_to account_path(@account), notice: "Account was successfully updated." }
        format.json { render :show, status: :ok, location: @account }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @account.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /accounts/1 or /accounts/1.json
  def destroy
    @account.destroy!

    respond_to do |format|
      format.html { redirect_to accounts_path, status: :see_other, notice: "Account was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_account
    @account = Account.find(params.expect(:id))
  end

  PERMITTED_PARAMS = [:name, :type, :opening_balance, :opening_date, :account_number, :sortcode].freeze
  PERMITTED_PARAMS_BANK_ACCOUNT = PERMITTED_PARAMS.dup.tap { |a| a.delete(:type) }.freeze
  PERMITTED_PARAMS_CREDIT_CARD = PERMITTED_PARAMS_BANK_ACCOUNT.dup.tap { |a| a.delete(:sortcode) }.freeze

  def new_account_params
    params.expect(account: PERMITTED_PARAMS)
  end

  # Only allow a list of trusted parameters through.
  def account_params
    if @account.is_a?(BankAccount)
      params.expect(bank_account: PERMITTED_PARAMS_BANK_ACCOUNT)
    elsif @account.is_a?(CreditCardAccount)
      params.expect(credit_card_account: PERMITTED_PARAMS_CREDIT_CARD)
    end
  end
end
