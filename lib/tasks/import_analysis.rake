require "csv"

namespace :import do
  desc "Import previous analysis data"
  task :categorised, [:input_file] => :environment do |_, args|

    # import data from excel file
    file = File.join(Rails.root, "db", args[:input_file])
    csv = CSV.read(file, headers: true)
    
    extract_categories(csv)

    build_importer_column_definitions(csv)
  end
end

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


    common_parameters[:account_id] = account_id
    common_parameters[:category_id] = category_id
    common_parameters[:transaction_type_column] = row

    ImportMatcher.find_or_create_by!(common_parameters)
  end
end

# Build the common parameters used for the Lloyds Bank CSV importer
# @param csv [CSV] the CSV file to build the parameters from
# @return [Hash] the common parameters used for the Lloyds Bank CSV importer
def build_import_column_definitions(headers, account)
  ImportColumnsDefinition.create!(
    account_id: account.id,
    date_column: headers.index("Date"),
    date_format: "%d/%m/%Y",
    transaction_type_column: headers.index("Transaction Type"),
    sortcode_column: headers.index("Sort Code"),
    account_number_column: headers.index("Account Number"),
    other_party_column: headers.index("Transaction Description"),
    debit_column: headers.index("Debit"),
    credit_column: headers.index("Credit"),
    balance_column: headers.index("Balance")
  )
end