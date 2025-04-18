# app/controllers/csv_analyses_controller.rb
class CsvAnalysesController < ApplicationController
  def create
    file = params[:csv_file]

    if file.nil?
      return render partial: "csv_analyses/error", locals: { message: "No file uploaded." }, status: :unprocessable_entity
    elsif file.content_type != "text/csv" && !file.original_filename.end_with?(".csv")
      return render partial: "csv_analyses/error", locals: { message: "Invalid file type." }, status: :unprocessable_entity
    end

    begin
      @csv_headers, @columns = ImportColumnsDefinition.analyze_csv(file)

      respond_to do |format|
        format.html { render partial: "csv_analyses/results", locals: { csv_headers: @csv_headers, columns: @columns } }
      end
    rescue CSV::MalformedCSVError => e
      render partial: "csv_analyses/error", locals: { message: "Error parsing CSV: #{e.message}" }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "Error analyzing CSV: #{e.message}\n#{e.backtrace.join("\n")}"
      render partial: "csv_analyses/error", locals: { message: "An unexpected error occurred." }, status: :internal_server_error
    ensure
      file.tempfile.close!
    end
  end
end
