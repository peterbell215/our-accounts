# Ruby Class to run a file import process.
class FileImporter
  attr_reader :file, :account, :import_column_definitions

  # Initialize the FileImporter
  # @param file [String] the path to the file to import
  # @param account [Account] the account to import the file into
  def initialize(file, account)
    @file = file
    @account = account
    @import_column_definitions = ImportColumnsDefinition.find_by(account_id: account.id)
  end

  # Run the file import process
  # @return [void]
  def import
    CSV.read(@file, headers: true).each do |row|
      imported_trx = ImportedTransactionFactory.build(csv_row, import_column_definitions)
      imported_trx.find_match
      imported_trx.sequence
      imported_trx.save!
    end
  end
end
