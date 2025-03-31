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

  # Run the file import process taking account of whether the CSV is in reverse date order.
  # @return [void]
  def import
    csv_data = CSV.read(@file, headers: import_column_definitions.header)
    index_range = (0...csv_data.count)
    index = (import_column_definitions.reversed ? index_range.reverse_each : index_range.each)

    index.each do |i|
      imported_trx = ImportedTransactionFactory.build(csv_data[i], import_column_definitions)
      imported_trx.find_match
      imported_trx.sequence
      imported_trx.save!
    end
  end
end
