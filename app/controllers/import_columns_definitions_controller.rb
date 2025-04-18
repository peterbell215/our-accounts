class ImportColumnsDefinitionsController < ApplicationController
  before_action :set_import_columns_definition, only: %i[ show edit update destroy ]

  # GET /import_columns_definitions or /import_columns_definitions.json
  def index
    @import_columns_definitions = ImportColumnsDefinition.all
  end

  # GET /import_columns_definitions/1 or /import_columns_definitions/1.json
  def show
  end

  # GET /import_columns_definitions/new
  def new
    @import_columns_definition = ImportColumnsDefinition.new
  end

  # GET /import_columns_definitions/1/edit
  def edit
  end

  # POST /import_columns_definitions or /import_columns_definitions.json
  def create
    @import_columns_definition = ImportColumnsDefinition.new(import_columns_definition_params)

    respond_to do |format|
      if @import_columns_definition.save
        format.html { redirect_to @import_columns_definition, notice: "Import columns definition was successfully created." }
        format.json { render :show, status: :created, location: @import_columns_definition }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @import_columns_definition.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /import_columns_definitions/1 or /import_columns_definitions/1.json
  def update
    respond_to do |format|
      if @import_columns_definition.update(import_columns_definition_params)
        format.html { redirect_to @import_columns_definition, notice: "Import columns definition was successfully updated." }
        format.json { render :show, status: :ok, location: @import_columns_definition }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @import_columns_definition.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /import_columns_definitions/1 or /import_columns_definitions/1.json
  def destroy
    @import_columns_definition.destroy!

    respond_to do |format|
      format.html { redirect_to import_columns_definitions_path, status: :see_other, notice: "Import columns definition was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_import_columns_definition
    @import_columns_definition = ImportColumnsDefinition.find(params.expect(:id))
  end

  # Only allow a list of trusted parameters through.
  def import_columns_definition_params
    params.expect(import_columns_definition: [:account_id, :header, :reversed, :credit_sign, :date_format, :date_column,
                                              :trx_type_column, :sortcode_column, :account_number_column, :other_party_column,
                                              :amount_column, :debit_column, :credit_column, :balance_column])

  end
end
