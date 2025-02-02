# Ruby Class to run a file import process.
class FileImporter
  attr_reader :file, :account, :column_definitions

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
    imported_transaction.date = Date.strptime(row[column_definitions.date_column], column_definitions.date_format)
    imported_transaction.import_account_id = account.id

    imported_transaction.description = row[column_definitions.other_party_column]
    imported_transaction.trx_type = row[column_definitions.transaction_type_column]

    if column_definitions.debit_column && column_definitions.credit_column
      imported_transaction.amount = if row[column_definitions.debit_column]
                                      Money.from_amount(-row[column_definitions.debit_column].to_f)
                                    elsif row[column_definitions.credit_column]
                                      Money.from_amount(row[column_definitions.credit_column].to_f)
                                    else
                                      raise ImportError, "No credit or debit amount specified."
                                    end
    end

    if column_definitions.balance_column
      imported_transaction.balance = Money.from_amount(row[column_definitions.balance_column].to_f)
    end

    imported_transaction
  end
end