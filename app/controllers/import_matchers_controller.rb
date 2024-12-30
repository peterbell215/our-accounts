class ImportMatchersController < ApplicationController
  before_action :set_import_matcher, only: %i[ show edit update destroy ]

  # GET /import_matchers or /import_matchers.json
  def index
    @import_matchers = ImportMatcher.all
  end

  # GET /import_matchers/1 or /import_matchers/1.json
  def show
  end

  # GET /import_matchers/new
  def new
    @import_matcher = ImportMatcher.new
  end

  # GET /import_matchers/1/edit
  def edit
  end

  # POST /import_matchers or /import_matchers.json
  def create
    @import_matcher = ImportMatcher.new(import_matcher_params)

    respond_to do |format|
      if @import_matcher.save
        format.html { redirect_to @import_matcher, notice: "Import matcher was successfully created." }
        format.json { render :show, status: :created, location: @import_matcher }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @import_matcher.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /import_matchers/1 or /import_matchers/1.json
  def update
    respond_to do |format|
      if @import_matcher.update(import_matcher_params)
        format.html { redirect_to @import_matcher, notice: "Import matcher was successfully updated." }
        format.json { render :show, status: :ok, location: @import_matcher }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @import_matcher.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /import_matchers/1 or /import_matchers/1.json
  def destroy
    @import_matcher.destroy!

    respond_to do |format|
      format.html { redirect_to import_matchers_path, status: :see_other, notice: "Import matcher was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_import_matcher
      @import_matcher = ImportMatcher.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def import_matcher_params
      params.expect(import_matcher: [ :account_id, :date_column, :date_format ])
    end
end
