# Counterparties: the suppliers and vendors the household deals with.  A Counterparty is an Account so
# that a transaction's counterparty is just another account, but it is not one of the household's own, so it
# has its own screens rather than sharing AccountsController's.
#
# Most of these records were created by AnalysisImporter and are named after raw statement text
# ("TESCO STORES 2889"), so renaming and deleting matter as much as creating.
class CounterpartiesController < ApplicationController
  before_action :set_counterparty, only: %i[ show edit update destroy ]

  # The columns the list can be ordered by.  Whitelisted because the value arrives as a query parameter,
  # and because only these four have a meaning to sort on.
  SORTS = %w[ name transactions total rules ].freeze

  # Alphabetical by default: with a few hundred counterparties, finding the one you meant is the common
  # errand.  Ordering by total is a click away, and is what shows which raw statement names are worth
  # renaming first.
  DEFAULT_SORT = "name".freeze

  # GET /counterparties or /counterparties.json
  #
  # Grouped queries rather than a count per row: the analysis import left a few hundred of these.
  def index
    @counts = Transaction.group(:counterparty_id).count
    @totals = Transaction.group(:counterparty_id).sum(:amount_pence)
    @rule_counts = ImportMatcher.group(:counterparty_id).count

    @sort = SORTS.include?(params[:sort]) ? params[:sort] : DEFAULT_SORT
    @direction = params[:direction] == "desc" ? "desc" : "asc"

    @counterparties = Counterparty.all.sort_by { |counterparty| sort_key(counterparty) }
    @counterparties.reverse! if @direction == "desc"
  end

  # GET /counterparties/1 or /counterparties/1.json
  #
  # Every dealing with this vendor, from whichever account it was paid from — the reason a counterparty is
  # modelled as an account at all.
  def show
    @transactions = @counterparty.counterparty_transactions
                                    .includes(:account, :category).newest_first
    @total = @transactions.sum(&:amount)
    @matchers = @counterparty.counterparty_matchers.includes(:account, :category).order(:description)
  end

  # GET /counterparties/new
  def new
    @counterparty = Counterparty.new
  end

  # GET /counterparties/1/edit
  def edit
  end

  # POST /counterparties or /counterparties.json
  def create
    @counterparty = Counterparty.new(counterparty_params)

    respond_to do |format|
      if @counterparty.save
        format.html { redirect_to @counterparty, notice: "Counterparty was successfully created." }
        format.json { render :show, status: :created, location: @counterparty }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @counterparty.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /counterparties/1 or /counterparties/1.json
  def update
    respond_to do |format|
      if @counterparty.update(counterparty_params)
        format.html { redirect_to @counterparty, notice: "Counterparty was successfully updated." }
        format.json { render :show, status: :ok, location: @counterparty }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @counterparty.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /counterparties/1 or /counterparties/1.json
  #
  # Account#counterparty_transactions and #counterparty_matchers are :nullify, so this releases the
  # transactions and rules rather than deleting them.
  def destroy
    @counterparty.destroy!

    respond_to do |format|
      format.html do
        redirect_to counterparties_path, status: :see_other,
                    notice: "Counterparty was successfully destroyed."
      end
      format.json { head :no_content }
    end
  end

  private
    # Sorted in Ruby rather than SQL because the counts and totals are grouped queries rather than columns
    # on accounts.  A few hundred rows makes that free.  Name is the tiebreaker throughout, so that equal
    # counts — and there are many rules with exactly one — come out in a stable, readable order.
    def sort_key(counterparty)
      name = counterparty.name.downcase

      case @sort
      when "transactions" then [ @counts[counterparty.id] || 0, name ]
      # Spending is negative, so ascending by total puts the largest spend first.
      when "total"        then [ @totals[counterparty.id] || 0, name ]
      when "rules"        then [ @rule_counts[counterparty.id] || 0, name ]
      else                     [ name ]
      end
    end

    def set_counterparty
      @counterparty = Counterparty.find(params.expect(:id))
    end

    # A counterparty is only a name.  The sort code, account number and balances Account carries are for
    # the household's own accounts.
    def counterparty_params
      params.expect(counterparty: [ :name ])
    end
end
