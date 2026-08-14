require "csv"

namespace :import do
  desc "Import categories from previous analysis data"
  task :extract_categories, [ :input_file ] => :environment do |_, args|
    created = Category.import_from_csv(Rails.root.join("db", args[:input_file]))
    puts "Created #{created} categories."
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

# @return [Hash] the common parameters used for the Lloyds Bank CSV importer
# @param [Object] headers
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
