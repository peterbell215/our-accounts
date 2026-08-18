class CategoriesController < ApplicationController
  before_action :set_category, only: %i[ show edit update destroy ]

  # The columns the list can be ordered by.  Whitelisted because the value arrives as a query parameter
  # and is interpolated into the ORDER BY.
  SORTS = %w[ name description ].freeze

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
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @category.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /categories/1 or /categories/1.jsonmain
  def destroy
    @category.destroy!

    respond_to do |format|
      format.html { redirect_to categories_path, status: :see_other, notice: "Category was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
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
      params.expect(category: [ :name, :description ])
    end
end
