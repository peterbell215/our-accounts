# lib/tasks/gen_sample_data.rake
require Rails.root.join("spec", "support", "account_trx_data_generator.rb")
require "factory_bot_rails"

namespace :data do
  desc "Generates sample transaction data for different types of accounts and saves it to the database."
  task create_sample_data: :environment do
    puts "Starting sample data generation..."

    # --- Step 1: clear out the database.
    Rake::Task["db:truncate_all"]

    # Create accounts if they don't exist
    lloyds_account = Account.find_by(name: "Lloyds Account") || FactoryBot.create(:lloyds_account)
    barclaycard_account = Account.find_by(name: "Barclaycard") || FactoryBot.create(:barclay_card_account)

    # Generate data for both account types
    generate_account_data(lloyds_account)
    generate_account_data(barclaycard_account, :barclaycard_import_columns_definition)

    puts "\nSample data generation task finished successfully."
  rescue StandardError => e
    # Catch potential errors during generation or saving
    puts "\nError encountered during sample data generation:"
    puts "Message: #{e.message}"
    puts "Backtrace:\n#{e.backtrace.join("\n")}"
    abort("Sample data generation failed.") # Stop the task on error
  end

  def generate_account_data(account, import_columns_definition_factory = nil)
    puts "\nGenerating data for account: #{account.name}"

    # Initialize the generator with appropriate parameters
    generator = AccountTrxDataGenerator.new(
      account: account,
      import_columns_definition_factory: import_columns_definition_factory
    )

    puts "Instantiated generator for account: #{generator.account.name} (ID: #{generator.account.id})"

    puts "Generating transaction data in memory..."
    # Call generate to populate the generator's @transactions array
    generator.generate
    puts "Generated #{generator.transactions.count} transactions in memory."

    puts "Writing generated transactions to the database..."
    # Call write_to_db to save the generated transactions
    generator.write_to_db # Assuming write_to_db returns the count
    puts "Successfully saved #{generator.transactions.count} transactions to the database"
  end
end
