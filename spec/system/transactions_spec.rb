require 'rails_helper'
# Helpers are now included globally via rails_helper.rb

# Include the helper modules in the RSpec configuration
include ActionView::Helpers::NumberHelper
include MoneyRails::ActionViewExtension
include ActionView::RecordIdentifier

RSpec.describe "Transactions", type: :system do
  let!(:lloyds_account) { Account.find_by(name: "Lloyds Account") || FactoryBot.create(:lloyds_account) }

  before(:all) do
    lloyds_account = Account.find_by(name: "Lloyds Account")
    generator = AccountTrxDataGenerator.new(account: lloyds_account) # Pass the account here
    generator.generate(output: :db)
  end

  it "displays transactions for the Lloyds account correctly" do
    visit account_path(lloyds_account) # Assuming this is the correct path to view transactions

    # Check page title or heading
    expect(page).to have_content("Transactions") # Or "Transactions for Lloyds Account"

    # Fetch the first transaction from the DB for comparison
    # Ensure consistent ordering, e.g., by date then ID
    first_db_transaction = lloyds_account.transactions.order(:date, :id).first
    expect(first_db_transaction).not_to be_nil # Ensure a transaction exists

    # Find the corresponding row on the page using dom_id
    transaction_row_selector = "##{dom_id(first_db_transaction)}"
    expect(page).to have_css(transaction_row_selector)

    within transaction_row_selector do
      expected_date_str = first_db_transaction.date.strftime("%-d %B %Y")
      expect(find('.div-table-col:nth-child(2) span')).to have_content(expected_date_str)

      # Description: Find the span in the description column
      expect(find('.div-table-col:nth-child(3) span').text).to eq(first_db_transaction.description)

      # Category: Find the selected option in the category column's select (or span if displayed differently)
      # For persisted rows, it might be a span or just text. Assuming span for now.
      # expect(find('.div-table-col:nth-child(4)')).to have_select(with_selected: first_db_transaction.category.name)

      # Amount: Find the span in the amount column and compare formatted amount
      expected_amount_str = humanized_money_with_symbol(first_db_transaction.amount)
      expect(find(".div-table-col.currency:nth-child(6) span").text).to eq(expected_amount_str)
    end
  end
end
