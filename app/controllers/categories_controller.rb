class CategoriesController < ApplicationController
  before_action :set_category, only: %i[ show edit update destroy ]

  # The columns the list can be ordered by.  Whitelisted because the value arrives as a query parameter
  # and is interpolated into the ORDER BY.
  SORTS = %w[ name description forecast_method ].freeze

  # Alphabetical by default: a category is looked up by name everywhere else in the application, so the
  # list reads the same way as the dropdowns do.
  DEFAULT_SORT = "name".freeze

  # GET /categories or /categories.json
  def index
    @sort = SORTS.include?(params[:sort]) ? params[:sort] : DEFAULT_SORT
    @direction = params[:direction] == "desc" ? "desc" : "asc"

    @categories = Category.order(ordering)
  end

  # GET /categories/1 or /categories/1.json
  def show
  end

  # GET /categories/new
  def new
    @category = Category.new
  end

  # GET /categories/1/edit
  def edit
    @payments = regular_payments
  end

  # POST /categories or /categories.json
  def create
    @category = Category.new(category_params)

    respond_to do |format|
      if @category.save
        format.html { redirect_to @category, notice: "Category was successfully created." }
        format.json { render :show, status: :created, location: @category }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @category.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /categories/1 or /categories/1.json
  def update
    respond_to do |format|
      if @category.update(category_params)
        format.html { redirect_to @category, notice: "Category was successfully updated." }
        format.json { render :show, status: :ok, location: @category }
      else
        @payments = regular_payments
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @category.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /categories/1 or /categories/1.jsonmain
  def destroy
    # destroy rather than destroy!: a category any rule still assigns is refused by :restrict_with_error, and
    # the reader needs to be told which rules to deal with, not shown a 500.
    if @category.destroy
      respond_to do |format|
        format.html { redirect_to categories_path, status: :see_other, notice: "Category was successfully destroyed." }
        format.json { head :no_content }
      end
    else
      respond_to do |format|
        format.html { redirect_to @category, status: :see_other, alert: destroy_refused_alert }
        format.json { render json: @category.errors, status: :unprocessable_entity }
      end
    end
  end

  private
    # Every payee in this category the forecast has considered, so that the frequencies it inferred can be
    # seen and corrected here, beside the choice of method they belong to.
    #
    # Built from a whole Forecast::Month rather than a loader of its own.  That costs two queries this
    # screen has no use for — every category, and the averaging window — and buys the guarantee that what
    # is listed here is exactly what the forecast is using, which is the entire point of the screen.
    #
    # `Forecast::Month.default_month` rather than today's month, for the reason the forecast screen opens
    # there too: statements are imported in arrears, so the calendar's current month usually holds nothing,
    # and asked about it every payee in the category reads as having gone quiet.  It also keeps this screen
    # and the workings page answering about the same month, which is the only way the two can be compared.
    #
    # @return [Array<Forecast::Payment>, nil] nil where the category is not predicted this way
    def regular_payments
      # The *persisted* method rather than the one on the form.  After a failed update @category carries
      # the method that was attempted, while the forecast is built from what is actually in the database —
      # so reading the attribute directly would ask a monthly-average line for its payments.
      return nil unless @category.forecast_method_was == "regular_payments"

      Forecast::Month.new(month: Forecast::Month.default_month).line_for(@category).strategy.candidates
    end

    # Names the rules standing in the way, since the fix is to recategorise or delete them and they live on
    # another screen.
    def destroy_refused_alert
      rules = @category.import_matchers.includes(:account)
      "#{@category.name} cannot be destroyed while #{helpers.pluralize(rules.size, 'import rule')} " \
        "still assigns it: #{rules.first(5).map(&:description).to_sentence}" \
        "#{rules.size > 5 ? ', and others' : ''}.  Change or delete those rules first."
    end

    # Case-insensitively, or "Utilities" would sort before "groceries" under SQLite's binary collation and
    # the list would read as though it were in no order at all.  Name breaks the tie, so categories with
    # no description — which sort together, SQLite putting NULLs first — still come out readable and in a
    # stable order.
    #
    # Built through Arel rather than as a string: the column arrives as a query parameter, and although
    # SORTS already confines it to two values, no part of a query worth writing twice should be spelled
    # out by hand.
    def ordering
      [ @direction == "desc" ? lower(@sort).desc : lower(@sort).asc, lower(DEFAULT_SORT).asc ]
    end

    def lower(column)
      Arel::Nodes::NamedFunction.new("LOWER", [ Category.arel_table[column] ])
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_category
      @category = Category.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def category_params
      params.expect(category: [ :name, :description, :forecast_method, :forecast_months ])
    end
end
