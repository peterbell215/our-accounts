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
      # @todo: add inner workings.

    end
  end
end