# Ruby Class to run a file import process.
class FileImporter
  # Initialize the FileImporter
  # @param file [String] the path to the file to import
  # @param account [Account] the account to import the file into
  def initialize(file, account)
    @file = file
    @account = account
    @column_definitions = ImportColumnsDefinition.find_by(account_id: account.id)
  end

  # Run the file import process
  # @return [void]
  def read
    CSV.read(@file, headers: true).each do |row|
      imported_transaction = import_row(row)

    end
  end

  # Import a single row of CSV data and generate an ImportedTransaction object with the data in a normalised form.
  # @param [CSV::Row] row
  # @return [ImportedTransaction]
  def import_row(row)
    imported_transaction = ImportedTransaction.new
    imported_transaction.date = Date.strptime(row[import_matcher.date_column], import_matcher.date_format)

    if import_column_definitions.debit_column && import_column_definitions.credit_column
      imported_transaction.amount = Money.new(row[import_matcher.amount_column].to_f * 100)
      imported_transaction.creditor = import_matcher.account
      imported_transaction.debitor = import_matcher.account
    end

    imported_transaction
  end

  private
end