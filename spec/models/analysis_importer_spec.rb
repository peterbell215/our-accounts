require 'rails_helper'

RSpec.describe AnalysisImporter, type: :model do
  # The real analysis spreadsheet holds live account data and is gitignored, so build a small one with
  # the same shape: a Lloyds statement export with a hand-added Category column.
  HEADERS = [ "Transaction Date", "Transaction Type", "Sort Code", "Account Number",
              "Transaction Description", "Debit Amount", "Credit Amount", "Balance", "Category" ].freeze

  let(:account) { create(:lloyds_account) }
  let(:file) { Rails.root.join('tmp', 'analysis_spec.csv') }

  # @param rows [Array<Array(String, String, Array)>] description, category, [sortcode, account_number]
  def write_analysis(rows)
    CSV.open(file, 'w', write_headers: true, headers: HEADERS) do |csv|
      rows.each_with_index do |(description, category, identity), i|
        sortcode, account_number = identity || [ "'30-00-00", "01234567" ]
        csv << [ "0#{i + 1}/04/2024", "DEB", sortcode, account_number,
                 description, "10.00", nil, "100.00", category ]
      end
    end
    file
  end

  after { FileUtils.rm_f(file) }

  describe 'deriving rules' do
    subject(:importer) { described_class.new(write_analysis(rows), account).import }

    context 'with straightforward labelled rows' do
      let(:rows) { [ [ "OCTOPUS ENERGY", "Utilities" ], [ "TESCO STORES 2889", "Shopping" ] ] }

      it 'creates one matcher per description' do
        expect { importer }.to change(ImportMatcher, :count).by(2)
      end

      it 'reports what it created' do
        expect(importer.matchers_created).to eq(2)
      end

      it 'ties the matcher to the account, category and a counterparty' do
        importer
        matcher = ImportMatcher.find_by(description: "OCTOPUS ENERGY")

        expect(matcher.account).to eq(account)
        expect(matcher.category.name).to eq("Utilities")
        expect(matcher.other_party).to be_a(TradingAccount)
        expect(matcher.other_party.name).to eq("OCTOPUS ENERGY")
      end

      it 'leaves the rule general rather than tying it to one transaction type' do
        importer
        matcher = ImportMatcher.find_by(description: "OCTOPUS ENERGY")

        expect(matcher.trx_type).to be_nil
        expect(matcher.description_is_regex).to be false
      end
    end

    context 'with a category the database does not yet hold' do
      let(:rows) { [ [ "HALFORDS E.COMM", "Bicycles" ], [ "OCTOPUS ENERGY", "Utilities" ] ] }

      it 'creates only the missing one' do
        # Utilities is already present, via REQUIRED_CATEGORIES in rails_helper.
        expect { importer }.to change(Category, :count).by(1)
        expect(Category.find_by(name: "Bicycles")).to be_present
      end
    end

    context 'when a description was filed under several categories' do
      let(:rows) do
        [ [ "MARKS&SPENCER PLC", "Shopping" ], [ "MARKS&SPENCER PLC", "Shopping" ],
          [ "MARKS&SPENCER PLC", "Travel" ] ]
      end

      it 'takes the most frequent category' do
        importer
        expect(ImportMatcher.find_by(description: "MARKS&SPENCER PLC").category.name).to eq("Shopping")
      end

      it 'creates a single rule' do
        expect { importer }.to change(ImportMatcher, :count).by(1)
      end
    end

    context 'when a description is filed under two categories equally often' do
      let(:rows) { [ [ "WATERSTONES", "Shopping" ], [ "WATERSTONES", "Travel" ] ] }

      it 'skips it rather than guessing' do
        expect { importer }.not_to change(ImportMatcher, :count)
      end

      it 'reports it' do
        expect(importer.ambiguous.map(&:first)).to eq([ "WATERSTONES" ])
      end
    end

    context 'when a description is too short to name a counterparty' do
      let(:rows) { [ [ "O2", "Utilities" ] ] }

      it 'still creates the rule, since the category is the point of it' do
        expect { importer }.to change(ImportMatcher, :count).by(1)

        matcher = ImportMatcher.find_by(description: "O2")
        expect(matcher.category.name).to eq("Utilities")
        expect(matcher.other_party).to be_nil
      end

      it 'reports that it could not name a counterparty' do
        expect(importer.counterparties_unnamed).to eq([ "O2" ])
      end

      it 'does not create a counterparty' do
        expect { importer }.not_to change(TradingAccount, :count)
      end
    end

    context 'when a description is longer than an account name may be' do
      let(:long) { "A" * 76 }
      let(:rows) { [ [ long, "Utilities" ] ] }

      it 'trims the counterparty name but keeps the rule matching the full description' do
        importer
        matcher = ImportMatcher.find_by(description: long)

        expect(matcher).to be_present
        expect(matcher.other_party.name.length).to eq(50)
      end
    end

    # The household analysis spreadsheet consolidates the current account, two credit cards and a store
    # card, so rows have to be attributed to the right account.
    context 'when the analysis consolidates several accounts' do
      let(:rows) do
        [ [ "OCTOPUS ENERGY", "Utilities" ],
          [ "AMAZON PRIME", "Subscriptions", [ "Visa", "BarclayCard" ] ],
          [ "PETER JONES", "Clothing", [ nil, "John Lewis" ] ] ]
      end

      it 'builds rules only from this account rows' do
        expect { importer }.to change(ImportMatcher, :count).by(1)
        expect(ImportMatcher.pluck(:description)).to eq([ "OCTOPUS ENERGY" ])
      end

      it 'reports how many rows it passed over' do
        expect(importer.other_account_rows).to eq(2)
      end

      it 'still takes categories from the whole file, since categories are global' do
        importer
        expect(Category.find_by(name: "Subscriptions")).to be_present
        expect(Category.find_by(name: "Clothing")).to be_present
      end
    end

    context 'when the file carries no account columns to discriminate on' do
      let(:file) { Rails.root.join('tmp', 'analysis_spec_bare.csv') }

      it 'accepts every row rather than silently building nothing' do
        CSV.open(file, 'w', write_headers: true,
                            headers: [ "Transaction Description", "Category" ]) do |csv|
          csv << [ "OCTOPUS ENERGY", "Utilities" ]
        end

        importer = described_class.new(file, account).import

        expect(importer.matchers_created).to eq(1)
        expect(importer.other_account_rows).to eq(0)
      end
    end

    context 'run twice over the same analysis' do
      let(:rows) { [ [ "OCTOPUS ENERGY", "Utilities" ] ] }

      it 'does not duplicate the rules' do
        described_class.new(write_analysis(rows), account).import
        expect { described_class.new(write_analysis(rows), account).import }
          .not_to change(ImportMatcher, :count)
      end
    end
  end

  describe 'the rules it produces' do
    let(:rows) { [ [ "OCTOPUS ENERGY", "Utilities" ] ] }

    it 'are usable by the raw statement import' do
      described_class.new(write_analysis(rows), account).import

      transaction = build(:transaction, account: account, date: Date.new(2024, 4, 1),
                                        description: "OCTOPUS ENERGY", amount: Money.from_amount(-50.00))
      transaction.find_match

      expect(transaction.category.name).to eq("Utilities")
      expect(transaction.other_party.name).to eq("OCTOPUS ENERGY")
    end
  end

  describe 'a file without a Category column' do
    it 'is rejected' do
      CSV.open(file, 'w') { |csv| csv << [ "Transaction Date", "Transaction Description" ] }

      expect { described_class.new(file, account).import }.to raise_error(ImportError, /Category/)
    end
  end
end
