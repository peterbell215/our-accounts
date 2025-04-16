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
    unless file
      return render json: { error: 'No file uploaded.' }, status: :bad_request
    end

    unless file.content_type == 'text/csv' || file.original_filename.end_with?('.csv')
      return render json: { error: 'Invalid file type. Please upload a CSV file.' }, status: :unprocessable_entity
    end


    begin
      # Read only the first few rows to get headers/structure without loading the whole file
      # Using headers: true attempts to read the first row as headers
      csv_options = { headers: true, return_headers: false } # Start assuming headers exist
      headers = nil
      first_data_row = nil

      # Try reading with headers
      begin
        csv = CSV.new(file.tempfile, **csv_options)
        headers = csv.first&.headers # Read just the header row
        file.tempfile.rewind # Rewind after reading headers
        csv = CSV.new(file.tempfile, **csv_options) # Re-initialize CSV object
        first_data_row = csv.first&.fields # Read the first data row
      rescue CSV::MalformedCSVError => e
        # If headers: true fails (e.g., inconsistent columns), try without it
        Rails.logger.warn("CSV parsing with headers failed: #{e.message}. Trying without headers.")
        headers = nil # Reset headers
        csv_options = { headers: false }
        file.tempfile.rewind
        csv = CSV.new(file.tempfile, **csv_options)
        first_data_row = csv.first # Read the first row as data
      end

      file.tempfile.rewind # Ensure file is rewound for potential re-reads if needed

      # Prepare columns data (index and value from first data row)
      columns_data = (first_data_row || []).map.with_index do |value, index|
        { index: index, value: value&.strip } # Strip whitespace
      end

      render json: {
        headers: headers, # Will be nil if headers: true failed or wasn't used
        columns: columns_data # Always contains {index, value} from the first row
      }

    rescue CSV::MalformedCSVError => e
      render json: { error: "Error parsing CSV: #{e.message}" }, status: :unprocessable_entity
    rescue => e # Catch other potential errors
      Rails.logger.error "Error analyzing CSV: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: 'An unexpected error occurred while processing the file.' }, status: :internal_server_error
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
