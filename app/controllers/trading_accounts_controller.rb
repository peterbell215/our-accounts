# Counterparties: the suppliers and vendors the household deals with.  A TradingAccount is an Account so
# that a transaction's other_party is just another account, but it is not one of the household's own, so it
# has its own screens rather than sharing AccountsController's.
#
# Most of these records were created by AnalysisImporter and are named after raw statement text
# ("TESCO STORES 2889"), so renaming and deleting matter as much as creating.
class TradingAccountsController < ApplicationController
  before_action :set_trading_account, only: %i[ show edit update destroy ]

  # GET /trading_accounts or /trading_accounts.json
  #
  # Ordered by what has been spent with each, since that is what decides whether a vendor is worth naming
  # properly.  Grouped queries rather than a count per row: the analysis import left a few hundred of these.
  def index
    @counts = Transaction.group(:other_party_id).count
    @totals = Transaction.group(:other_party_id).sum(:amount_pence)
    @rule_counts = ImportMatcher.group(:other_party_id).count

    # Spending is negative, so the smallest total is the largest spend.
    @trading_accounts = TradingAccount.all.sort_by { |account| [ @totals[account.id] || 0, account.name ] }
  end

  # GET /trading_accounts/1 or /trading_accounts/1.json
  #
  # Every dealing with this vendor, from whichever account it was paid from — the reason a counterparty is
  # modelled as an account at all.
  def show
    @transactions = @trading_account.counterparty_transactions
                                    .includes(:account, :category).newest_first
    @total = @transactions.sum(&:amount)
    @matchers = @trading_account.counterparty_matchers.includes(:account, :category).order(:description)
  end

  # GET /trading_accounts/new
  def new
    @trading_account = TradingAccount.new
  end

  # GET /trading_accounts/1/edit
  def edit
  end

  # POST /trading_accounts or /trading_accounts.json
  def create
    @trading_account = TradingAccount.new(trading_account_params)

    respond_to do |format|
      if @trading_account.save
        format.html { redirect_to @trading_account, notice: "Counterparty was successfully created." }
        format.json { render :show, status: :created, location: @trading_account }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @trading_account.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /trading_accounts/1 or /trading_accounts/1.json
  def update
    respond_to do |format|
      if @trading_account.update(trading_account_params)
        format.html { redirect_to @trading_account, notice: "Counterparty was successfully updated." }
        format.json { render :show, status: :ok, location: @trading_account }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @trading_account.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /trading_accounts/1 or /trading_accounts/1.json
  #
  # Account#counterparty_transactions and #counterparty_matchers are :nullify, so this releases the
  # transactions and rules rather than deleting them.
  def destroy
    @trading_account.destroy!

    respond_to do |format|
      format.html do
        redirect_to trading_accounts_path, status: :see_other,
                    notice: "Counterparty was successfully destroyed."
      end
      format.json { head :no_content }
    end
  end

  private
    def set_trading_account
      @trading_account = TradingAccount.find(params.expect(:id))
    end

    # A counterparty is only a name.  The sort code, account number and balances Account carries are for
    # the household's own accounts.
    def trading_account_params
      params.expect(trading_account: [ :name ])
    end
end
