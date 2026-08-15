require 'rails_helper'

RSpec.describe AnalysisCategoriser, type: :model do
  let(:account) { create(:lloyds_account) }
  let(:file) { Rails.root.join('tmp', 'categoriser_spec.csv') }

  after { FileUtils.rm_f(file) }

  # Writes an analysis sheet row for row against the transactions passed in, so date and balance line up
  # the way they would after a real import.
  # @param rows [Array<Array>] [transaction, category, identity]
  def write_analysis(rows)
    headers = [ "Transaction Date", "Sort Code", "Account Number", "Transaction Description",
                "Balance", "Category" ]

    CSV.open(file, 'w', write_headers: true, headers: headers) do |csv|
      rows.each do |transaction, category, identity|
        sortcode, account_number = identity || [ "'30-00-00", "01234567" ]
        csv << [ transaction.date.strftime("%d/%m/%Y"), sortcode, account_number,
                 transaction.description, format("%.2f", transaction.balance.to_f), category ]
      end
    end
    file
  end

  # @return [Transaction]
  def imported(description:, balance:, date: Date.new(2024, 4, 2), category: nil)
    create(:transaction, account: account, date: date, description: description,
                         amount: Money.from_amount(-10.00), balance: Money.from_amount(balance),
                         category: category)
  end

  describe 'applying labels' do
    it 'sets the category on a transaction that had none' do
      transaction = imported(description: "OCTOPUS ENERGY", balance: 100.00)
      result = described_class.new(write_analysis([ [ transaction, "Utilities" ] ]), account).apply

      expect(transaction.reload.category.name).to eq("Utilities")
      expect(result.assigned).to eq(1)
    end

    it 'overrides a category a rule got wrong, and says so' do
      transaction = imported(description: "SAINSBURYS PETROL", balance: 100.00,
                             category: Category.find_or_create_by!(name: "Shopping"))
      result = described_class.new(write_analysis([ [ transaction, "Travel" ] ]), account).apply

      expect(transaction.reload.category.name).to eq("Travel")
      expect(result.assigned).to eq(1)
      expect(result.corrected).to eq([ [ "SAINSBURYS PETROL", "Shopping", "Travel" ] ])
    end

    it 'leaves a category that was already right alone' do
      transaction = imported(description: "OCTOPUS ENERGY", balance: 100.00,
                             category: Category.find_or_create_by!(name: "Utilities"))
      result = described_class.new(write_analysis([ [ transaction, "Utilities" ] ]), account).apply

      expect(result.unchanged).to eq(1)
      expect(result.assigned).to eq(0)
      expect(result.corrected).to be_empty
    end

    it 'creates a category the database does not yet hold' do
      transaction = imported(description: "HALFORDS", balance: 100.00)

      expect { described_class.new(write_analysis([ [ transaction, "Bicycles" ] ]), account).apply }
        .to change(Category, :count).by(1)
      expect(transaction.reload.category.name).to eq("Bicycles")
    end
  end

  describe 'matching' do
    it 'distinguishes transactions sharing a date and description by their balance' do
      first  = imported(description: "EOE COOP FOOD", balance: 100.00)
      second = imported(description: "EOE COOP FOOD", balance: 90.00)

      described_class.new(write_analysis([ [ first, "Food" ], [ second, "Dine Out" ] ]), account).apply

      expect(first.reload.category.name).to eq("Food")
      expect(second.reload.category.name).to eq("Dine Out")
    end

    it 'records rows with no matching transaction rather than failing' do
      imported(description: "OCTOPUS ENERGY", balance: 100.00)
      ghost = build(:transaction, account: account, date: Date.new(2024, 4, 2),
                                  description: "NOT IMPORTED", balance: Money.from_amount(55.55))

      result = described_class.new(write_analysis([ [ ghost, "Utilities" ] ]), account).apply

      expect(result.assigned).to eq(0)
      expect(result.not_found.first).to include(Date.new(2024, 4, 2), "NOT IMPORTED")
    end

    it 'ignores rows belonging to another account in the same sheet' do
      mine = imported(description: "OCTOPUS ENERGY", balance: 100.00)
      theirs = imported(description: "AMAZON PRIME", balance: 90.00)

      described_class.new(
        write_analysis([ [ mine, "Utilities" ],
                         [ theirs, "Subscriptions", [ "Visa", "BarclayCard" ] ] ]), account
      ).apply

      expect(mine.reload.category.name).to eq("Utilities")
      expect(theirs.reload.category).to be_nil
    end

    it 'skips rows with no category, leaving those transactions untouched' do
      transaction = imported(description: "DAILY OD INT", balance: 100.00)
      result = described_class.new(write_analysis([ [ transaction, nil ] ]), account).apply

      expect(transaction.reload.category).to be_nil
      expect(result.assigned).to eq(0)
      expect(result.not_found).to be_empty
    end
  end

  describe 'the hand-edited date formats' do
    it 'reads dd-Mmm-yy as well as dd/mm/yyyy' do
      transaction = imported(description: "OCTOPUS ENERGY", balance: 100.00, date: Date.new(2024, 7, 10))

      CSV.open(file, 'w', write_headers: true,
                          headers: [ "Transaction Date", "Sort Code", "Account Number",
                                     "Transaction Description", "Balance", "Category" ]) do |csv|
        csv << [ "10-Jul-24", "'30-00-00", "01234567", "OCTOPUS ENERGY", "100.00", "Utilities" ]
      end

      described_class.new(file, account).apply

      expect(transaction.reload.category.name).to eq("Utilities")
    end
  end

  describe 'running it twice' do
    it 'changes nothing the second time' do
      transaction = imported(description: "OCTOPUS ENERGY", balance: 100.00)
      described_class.new(write_analysis([ [ transaction, "Utilities" ] ]), account).apply
      result = described_class.new(write_analysis([ [ transaction, "Utilities" ] ]), account).apply

      expect(result.assigned).to eq(0)
      expect(result.unchanged).to eq(1)
    end
  end

  describe 'a file missing the columns it needs' do
    it 'is rejected' do
      CSV.open(file, 'w') { |csv| csv << [ "Transaction Date", "Balance" ] }

      expect { described_class.new(file, account).apply }.to raise_error(ImportError, /Category/)
    end
  end
end
