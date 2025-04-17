# app/controllers/csv_analyses_controller.rb
class CsvAnalysesController < ApplicationController
  def create
    file = params[:csv_file]

    if file.nil?
      return render turbo_stream: "error", message: "No file uploaded."
    elsif file.content_type != "text/csv" && !file.original_filename.end_with?(".csv")
      return render turbo_stream: "error", message: "No file uploaded."
    end

    begin
      @csv_headers, @columns = ImportColumnsDefinition.analyze_csv(file)

      respond_to do |format|
        format.turbo_stream # This will implicitly look for create.turbo_stream.erb
        format.html { redirect_to somewhere_else, notice: "Analysis complete." } # Fallback
      end
    rescue CSV::MalformedCSVError => e
      return render turbo_stream: "error", message: "Error parsing CSV: #{e.message}"
    rescue => e # Catch other potential errors
      Rails.logger.error "Error analyzing CSV: #{e.message}\n#{e.backtrace.join("\n")}"
      return render turbo_stream: "error", message: "An unexpected error occurred while processing the file."
    ensure
      file.tempfile.close
    end
  end
end
