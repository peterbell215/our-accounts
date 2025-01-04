# Ruby Class to run a file import process.
class FileImporter
  # Initialize the FileImporter
  # @param file [String] the path to the file to import
  # @param account [Account] the account to import the file into
  def initialize(file, account)
    @file = file
    @account = account
    @column_definitions = ImportColumnsDefinition.where(account: account)
  end

  def import_row(row)
    imported_transaction = ImportedTransaction.new
    imported_transaction.date = Date.strptime(row[import_matcher.date_column], import_matcher.date_format)

    if import_column_definitions.debit_column && import_column_definitions.credit_column
      imported_transaction.amount = Money.new(row[import_matcher.amount_column].to_f * 100)
      imported_transaction.creditor = import_matcher.account
      imported_transaction.debitor = import_matcher.account
    end

    imported_transaction.save
  end

  # Run the file import process
  # @return [void]
  def run
    csv = CSV.read(file, headers: true)

    extract_categories(csv)

    build_importer_column_definitions(csv)
  end

  private

  # Extract categories from the CSV file
  # @param csv [CSV] the CSV file to extract categories from
  # @return [void]
  def extract_categories(csv)
    csv.each do |row|
      # remove any leading single quotes (used by Excel to de-mark a String) from each row element
      row = row.to_h.transform_values! {|s| s && s[0] == "'" ? s[1..] : s }

      next if row["Category"].nil?
      Category.find_or_create_by!(name: row["Category"])
    end
  end

  # Build the importers for the Lloyds Bank CSV file
  # @param csv [CSV] the CSV file to build the importers from
  # @return [void]
  def build_import(csv)
    account_id = Account.where(name: "Joint").select(:id).first.id

    common_parameters = build_common_parameters(csv)

    csv.each do |row|
      category = Category.where(name: row["Category"]).select(:id).first
      next if category.nil?
      category_id = category.id
    end
  end
end
