# Loading a statement into an account, from the file the bank produced.
#
# Its own controller rather than extra actions on AccountsController, the same habit as CsvAnalysesController
# and CounterpartyMergesController: the operation is the noun.  All the work is FileImporter's; this decides
# what to show, what to say afterwards, and what to refuse before the file is opened at all.
#
# **One step, and all or nothing.**  There is no preview to confirm, because FileImporter runs the whole file
# inside one database transaction: either every row lands or none does.  A preview would have to keep the
# uploaded file alive between two requests to buy a reassurance that atomicity already gives, so every
# failure message here can open by saying nothing was imported and be telling the truth.
#
# **The upload is a plain multipart parameter**, as on the CSV analysis screen.  ActiveStorage's engine is
# configured but has no tables and is used nowhere, and a statement is read once and never wanted again —
# there is nothing here worth attaching to a record.
class StatementImportsController < ApplicationController
  before_action :set_account
  before_action :set_definition

  # GET /accounts/:account_id/statement_imports/new
  def new
  end

  # POST /accounts/:account_id/statement_imports
  def create
    return redirect_to new_account_statement_import_path(@account), alert: no_definition_alert if @definition.nil?

    file = params[:csv_file]

    if file.nil?
      return redirect_to new_account_statement_import_path(@account), alert: "Choose a CSV file to import."
    elsif file.content_type != "text/csv" && !file.original_filename.end_with?(".csv")
      return redirect_to new_account_statement_import_path(@account), alert: not_a_csv_alert
    end

    begin
      importer = FileImporter.new(file.tempfile.path, @account).import

      redirect_to account_path(@account), notice: imported_notice(importer)
    rescue ImportError => e
      # ImportError only, deliberately unlike CsvAnalysesController's blanket rescue.  That one renders into
      # a Turbo frame, where an unhandled exception leaves the frame blank with nothing said; this one
      # redirects, so Rails' own error report is the better account of a genuine bug — and the transaction
      # has already rolled back, so nothing is at stake in letting one through.
      #
      # The reassurance goes first because it is what the reader most needs to know, and it is only true
      # because the whole file is one database transaction.  #upcase_first because the messages are written
      # to read as a clause — "line 8: ..." — and following a full stop they have to start a sentence.
      redirect_to new_account_statement_import_path(@account),
                  alert: "Nothing was imported.  #{e.message.upcase_first}"
    ensure
      file.tempfile.close!
    end
  end

  private

    def set_account
      @account = Account.find(params[:account_id])
    end

    # The same lookup FileImporter makes, rather than @account.import_columns_definitions.first, so the screen
    # and the import can never disagree about which layout is in force.  Account has a has_many here and
    # nothing enforces one per account, despite everything written about it assuming so.
    def set_definition
      @definition = ImportColumnsDefinition.find_by(account_id: @account.id)
    end

    # What landed, in the order the reader wants it: how many, over what period, and how much of it the rules
    # already filed.  The skipped clause appears only when something was skipped — on a first import it would
    # be a nought on every screen — the same judgement CounterpartyMergesController makes about frequencies.
    #
    # @param [FileImporter] importer
    # @return [String]
    def imported_notice(importer)
      return "That file has no rows in it, so nothing was imported." if importer.rows_read.zero?

      if importer.imported.zero?
        return "All #{helpers.pluralize(importer.rows_read, 'row')} in that file are already loaded in " \
               "#{@account.name}, so nothing was imported."
      end

      period = "#{helpers.short_date(importer.imported_from)} to #{helpers.short_date(importer.imported_to)}"
      notice = +"Imported #{helpers.pluralize(importer.imported, 'transaction')} into #{@account.name}, #{period}"
      notice << ", and skipped #{helpers.pluralize(importer.skipped, 'row')} already loaded" if importer.skipped.positive?
      notice << ".  #{importer.categorised} categorised by rule, #{importer.uncategorised} left uncategorised."
    end

    # @return [String]
    def no_definition_alert
      "#{@account.name} has no column layout yet, so nothing knows how to read its statements."
    end

    # @return [String]
    def not_a_csv_alert
      "That file is not a CSV.  Statements download from the bank as CSV; if you have opened it in a " \
      "spreadsheet since, save it as CSV again."
    end
end
