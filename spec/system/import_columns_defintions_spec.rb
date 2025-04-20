require 'rails_helper'

RSpec.describe "ImportColumnsDefinitions", type: :system do
  FILENAME = "lloyds_import_file.csv"
  FILENAME_WITH_PATH = Rails.root.join('tmp', FILENAME)

  before(:all) do
    lloyds_account = FactoryBot.create(:lloyds_account)
    lloyds_import_file_generator = AccountTrxDataGenerator.new(account: lloyds_account)
    lloyds_import_file_generator.generate(output: FILENAME_WITH_PATH)
  end

  let(:account) { Account.find_by_name("Lloyds Account") }
  let(:expected_headers) do
    FactoryBot.attributes_for(:lloyds_import_columns_definition)
              .select { |a, v| a =~ /_column\z/ }
              .transform_keys{ |key| key.to_s.humanize }
  end

  it "allows creating a definition by analyzing a CSV and dragging columns" do
    visit new_import_columns_definition_path

    # --- Fill in basic details ---
    select account.name, from: 'import_columns_definition_account_id'
    fill_in 'Date format', with: '%d/%m/%Y' # Example format

    # --- Analyze CSV ---
    uncheck 'Header'

    # Attach the file to the hidden input used by the analyzer form
    attach_file 'csv_file', FILENAME_WITH_PATH

    # Click the analyze button within the analyzer's form scope
    within('.csv-analyzer-container') do
      click_button 'Analyze File'
    end

    # --- Wait for and Verify Analysis Results ---
    # Wait for the turbo frame to load and Stimulus controller to update checkbox
    expect(page).to have_field('Header', checked: true, wait: 5) # Should be checked automatically

    index = (0..).each;

    expected_headers.each_pair do |target_column, extracted_column|
      next if extracted_column.nil?

      text_from_csv = "#{index.next}: #{extracted_column}"
      expect(page).to have_selector('.column-item', text: text_from_csv), "failed to find selector #{text_from_csv}"

      source = find('.column-item', text: text_from_csv )
      target = find_field(target_column)

      source.drag_to(target)

      expect(target.value).to eq(extracted_column)
    end

    # --- Save Definition ---
    click_button 'Create Import columns definition'

    # --- Verify Result ---
    expect(page).to have_content('Import columns definition was successfully created.') # Adjust flash message if needed
    expect(ImportColumnsDefinition.count).to eq(1)

    definition = ImportColumnsDefinition.first

    FactoryBot.attributes_for(:lloyds_import_columns_definition).each_pair do |field, expected_value|
      next if field == :account
      expect(definition[field]).to eq(expected_value)
    end
  end
end
