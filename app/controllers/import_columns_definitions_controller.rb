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

  # POST /import_columns_definitions/analyze_csv
  def analyze_csv
    file = params[:csv_file]

    if file.nil?
      return render json: { error: "No file uploaded." }, status: :bad_request
    elsif file.content_type != "text/csv" && !file.original_filename.end_with?(".csv")
      return render json: { error: "Invalid file type. Please upload a CSV file." }, status: :unprocessable_entity
    end

    begin
      headers, columns_data = ImportColumnsDefinition.analyze_csv(file)

      render json: {
        headers: headers, # Will be nil if headers: true failed or wasn't used
        columns: columns_data # Always contains {index, value} from the first row
      }
    rescue CSV::MalformedCSVError => e
      render json: { error: "Error parsing CSV: #{e.message}" }, status: :unprocessable_entity
    rescue => e # Catch other potential errors
      Rails.logger.error "Error analyzing CSV: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: "An unexpected error occurred while processing the file." }, status: :internal_server_error
    ensure
      file.tempfile.close
      # file.tempfile.unlink # Tempfile is usually automatically cleaned up, but uncomment if needed
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_import_columns_definition
    @import_columns_definition = ImportColumnsDefinition.find(params.expect(:id))
  end

  # Only allow a list of trusted parameters through.
  def import_columns_definition_params
    params.fetch(:import_columns_definition, {})
  end
end
