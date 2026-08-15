require 'rails_helper'

RSpec.describe AccountSeeder, type: :model do
  let(:directory) { Rails.root.join('tmp', 'seeder_spec') }
  let(:raw) { 'raw.csv' }
  let(:analysis) { 'analysis.csv' }

  RAW_HEADERS = [ "Transaction Date", "Transaction Type", "Sort Code", "Account Number",
                  "Transaction Description", "Debit Amount", "Credit Amount", "Balance" ].freeze

  before { FileUtils.mkdir_p(directory) }
  after { FileUtils.rm_rf(directory) }

  # Writes a raw download in the shape Lloyds exports one: newest row first, debits as positive numbers
  # in their own column, and a running balance.
  # @param entries [Array<Array(String, String, Float)>] date, description, amount (negative for a debit)
  #   given newest first
  def write_raw(entries, opening: 1000.00)
    running = opening
    chronological = entries.reverse.map do |date, description, amount|
      running += amount
      [ date, description, amount, running ]
    end

    CSV.open(directory.join(raw), 'w', write_headers: true, headers: RAW_HEADERS) do |csv|
      chronological.reverse_each do |date, description, amount, balance|
        csv << [ date, "DEB", "'30-00-00", "01234567", description, format("%.2f", -amount), nil,
                 format("%.2f", balance) ]
      end
    end
  end

  # @param entries [Array<Array(String, String, Float, String)>] date, description, balance, category
  def write_analysis(entries)
    headers = RAW_HEADERS + [ "Category" ]

    CSV.open(directory.join(analysis), 'w', write_headers: true, headers: headers) do |csv|
      entries.each do |date, description, balance, category|
        csv << [ date, "DEB", "'30-00-00", "01234567", description, "1.00", nil,
                 format("%.2f", balance), category ]
      end
    end
  end

  subject(:seeder) do
    described_class.new(account_name: "Joint", raw_statement: raw, analysis: analysis,
                        directory: directory)
  end

  describe 'a database with nothing in it' do
    before do
      # Opening 1000.00; oldest first the balances run 980.00 then 970.00.
      write_raw([ [ "03/01/2024", "TESCO STORES", -10.00 ], [ "02/01/2024", "OCTOPUS ENERGY", -20.00 ] ])
      write_analysis([ [ "02/01/2024", "OCTOPUS ENERGY", 980.00, "Utilities" ] ])
    end

    it 'creates the account, deriving its opening position from the statement' do
      seeder.seed
      account = Account.find_by(name: "Joint")

      expect(account).to be_a(BankAccount)
      expect(account.sortcode).to eq("30-00-00")
      expect(account.account_number).to eq("01234567")
      # The oldest row is the last one: -20.00 leaving 980.00, so the account opened on 1000.00.
      expect(account.opening_balance).to eq(Money.from_amount(1000.00))
      expect(account.opening_date).to eq(Date.new(2024, 1, 1))
    end

    it 'describes how the statements are laid out' do
      seeder.seed
      definition = ImportColumnsDefinition.find_by(account: seeder.account)

      expect(definition.date_column).to eq("Transaction Date")
      expect(definition.reversed).to be true
    end

    it 'imports the transactions with balances that reconcile' do
      seeder.seed

      expect(seeder.transactions_imported).to eq(2)
      expect(seeder.account.transactions.order(:date).map { |t| t.balance.to_f }).to eq([ 980.00, 970.00 ])
    end

    it 'derives the rules and applies the hand-assigned categories' do
      seeder.seed

      expect(seeder.rules_created).to eq(1)
      expect(seeder.labels_applied).to eq(0) # the rule already categorised it correctly
      expect(seeder.account.transactions.find_by(description: "OCTOPUS ENERGY").category.name)
        .to eq("Utilities")
    end
  end

  describe 'running it again' do
    before do
      write_raw([ [ "02/01/2024", "OCTOPUS ENERGY", -20.00 ] ])
      write_analysis([ [ "02/01/2024", "OCTOPUS ENERGY", 980.00, "Utilities" ] ])
      seeder.seed
    end

    it 'does not import the transactions twice' do
      second = described_class.new(account_name: "Joint", raw_statement: raw, analysis: analysis,
                                   directory: directory)

      expect { second.seed }.not_to change(Transaction, :count)
      expect(second.import_skipped).to be true
    end

    it 'reuses the account rather than creating another' do
      second = described_class.new(account_name: "Joint", raw_statement: raw, analysis: analysis,
                                   directory: directory)

      expect { second.seed }.not_to change(Account, :count)
    end
  end

  describe 'reporting what it cannot do' do
    it 'knows when the statement files are absent' do
      expect(seeder.missing_sources.map(&:basename).map(&:to_s)).to contain_exactly(raw, analysis)
    end

    it 'knows when only one is absent' do
      write_raw([ [ "02/01/2024", "OCTOPUS ENERGY", -20.00 ] ])

      expect(seeder.missing_sources.map(&:basename).map(&:to_s)).to eq([ analysis ])
    end

    it 'knows when it has not been told what to seed' do
      expect(described_class.new(account_name: nil, raw_statement: raw, analysis: analysis,
                                 directory: directory)).not_to be_configured
    end

    it 'is configured once all three are given' do
      expect(seeder).to be_configured
    end
  end

  describe '.from_credentials' do
    it 'returns nothing when the credentials carry no seed_data' do
      allow(Rails.application.credentials).to receive(:seed_data).and_return(nil)

      expect(described_class.from_credentials).to be_nil
    end

    it 'builds a seeder from the credentials when they are present' do
      allow(Rails.application.credentials).to receive(:seed_data)
        .and_return(ActiveSupport::OrderedOptions.new.merge(
                      account_name: "Joint", raw_statement: raw, analysis: analysis))

      expect(described_class.from_credentials(directory: directory).account_name).to eq("Joint")
    end
  end
end
