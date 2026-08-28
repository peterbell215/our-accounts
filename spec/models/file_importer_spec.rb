require 'rails_helper'

RSpec.describe FileImporter, type: :class do
  describe 'Lloyds Import' do
    before(:all) do
      # Create Lloyds test data
      @lloyds_account = FactoryBot.create(:lloyds_account)
      FactoryBot.create(:lloyds_import_columns_definition)
      ImportTestHelpers.generate_test_file(@lloyds_account)
    end

    after(:all) do
      ImportTestHelpers.cleanup_test_file(@lloyds_account)
      Account.destroy_all
    end

    let(:lloyds_account) { Account.find_by_name("Lloyds Account") }
    let(:lloyds_filename) { ImportTestHelpers.get_filename_with_path(lloyds_account) }

    it 'has generated a suitable test file' do
      expect(File.exist?(lloyds_filename)).to be true
    end

    describe 'imports the generated file correctly' do
      subject!(:file_importer) { FileImporter.new(lloyds_filename, lloyds_account).import }

      specify { expect(lloyds_account.transactions.count).to eq(17) }
    end

    describe 'reporting what it did' do
      subject(:importer) { FileImporter.new(lloyds_filename, lloyds_account).import }

      it 'counts the rows it read and loaded, and the period they cover' do
        expect(importer).to have_attributes(rows_read: 17, imported: 17, skipped: 0)
        expect(importer.imported_from).to eq(lloyds_account.transactions.minimum(:date))
        expect(importer.imported_to).to eq(lloyds_account.transactions.maximum(:date))
      end

      it 'splits what the rules caught from what they did not' do
        FactoryBot.create(:import_matcher, account: lloyds_account, description: 'TESCO STORES 2889',
                                           category: Category.find_by(name: 'Shopping'))

        expect(importer.categorised).to eq(10)
        expect(importer.uncategorised).to eq(7)
        expect(importer.categorised + importer.uncategorised).to eq(importer.imported)
      end
    end

    describe 'a file that has already been loaded' do
      before { FileImporter.new(lloyds_filename, lloyds_account).import }

      # The everyday case the screen exists for: statements are downloaded by date range and the ranges
      # overlap, so the same rows arrive again and must not be doubled up.
      it 'skips every row rather than importing it twice' do
        expect { @second = FileImporter.new(lloyds_filename, lloyds_account).import }
          .not_to change(Transaction, :count)

        expect(@second).to have_attributes(rows_read: 17, imported: 0, skipped: 17)
      end

      it 'imports only the rows the account does not already hold' do
        lloyds_account.transactions.newest_first.first(3).each(&:destroy!)

        importer = FileImporter.new(lloyds_filename, lloyds_account).import

        expect(importer).to have_attributes(imported: 3, skipped: 14)
        expect(lloyds_account.transactions.count).to eq(17)
      end

      # The period reported is what landed, not what the file covered.  Catching up means loading a file
      # that mostly repeats what is already here, so reporting the file's range claims a year's worth for
      # what was really the last few days of it.
      it 'reports the period the rows it actually imported cover' do
        restored = lloyds_account.transactions.newest_first.first(3).to_a
        restored.each(&:destroy!)

        importer = FileImporter.new(lloyds_filename, lloyds_account).import

        expect(importer.imported_from).to eq(restored.map(&:date).min)
        expect(importer.imported_to).to eq(restored.map(&:date).max)
        expect(importer.imported_from).to be > lloyds_account.transactions.minimum(:date)
      end

      # The restored rows have to carry the same running balance they had before, or the account no longer
      # reconciles against the statement it came from.
      it 'restores the balances of the rows it re-imports' do
        expected = lloyds_account.transactions.newest_first.first(3).map { |trx| [ trx.date, trx.balance ] }
        lloyds_account.transactions.newest_first.first(3).each(&:destroy!)

        FileImporter.new(lloyds_filename, lloyds_account).import

        expect(lloyds_account.transactions.newest_first.first(3).map { |trx| [ trx.date, trx.balance ] })
          .to eq(expected)
      end
    end

    describe 'a file that does not reconcile' do
      # Every row is its own save, so without a transaction around the loop the rows before the bad one would
      # stay behind.  This is the assertion that the whole file is all or nothing.
      it 'imports nothing at all when one balance disagrees' do
        tampered = CSV.read(lloyds_filename, headers: true)
        tampered[3]["Balance"] = "999999.99"
        CSV.open(lloyds_filename, 'w', write_headers: true, headers: tampered.headers) do |csv|
          tampered.each { |row| csv << row }
        end

        begin
          expect { FileImporter.new(lloyds_filename, lloyds_account).import }
            .to raise_error(ImportError, /the statement says the balance is/)

          # The rows before the bad one were saved one at a time and would still be here without the
          # transaction wrapping the loop.  This is the assertion that a refused file changes nothing.
          expect(Transaction.count).to eq(0)
        ensure
          ImportTestHelpers.generate_test_file(lloyds_account)
        end
      end

      it 'names the line, the row and both balances' do
        lloyds_account.update!(opening_balance: Money.from_amount(999.99))

        expect { FileImporter.new(lloyds_filename, lloyds_account).import }
          .to raise_error(ImportError, /line \d+: .+ — the statement says the balance is .+ where the account works out/)
      end
    end

    describe 'preconditions it refuses rather than computes through' do
      # A transaction added by hand never runs #sequence, so it has neither a balance nor a day_index.  Until
      # importing had a screen this could not arise, because a statement was only ever loaded into an empty
      # account.
      it 'refuses to chain onto a hand-added transaction that has no balance' do
        oldest = CSV.read(lloyds_filename, headers: true).to_a.last
        hand_added = lloyds_account.transactions.create!(
          date: Date.strptime(oldest[0].strip, "%d/%m/%Y") + 1, description: 'CASH', amount: Money.from_amount(-10)
        )

        expect(hand_added.balance).to be_nil
        expect { FileImporter.new(lloyds_filename, lloyds_account).import }
          .to raise_error(ImportError, /has no balance of its own.*added by hand/m)
      end

      # A mis-mapped column used to be reported as a balance that did not reconcile, because the missing
      # value read as nil and nil.to_f is 0.00 — the symptom rather than the cause, and it sent the reader
      # to the wrong screen.
      it 'names a column the file does not have, rather than reporting a balance of zero' do
        ImportColumnsDefinition.find_by(account_id: lloyds_account.id).update!(balance_column: "Closing Balance")

        expect { FileImporter.new(lloyds_filename, lloyds_account).import }
          .to raise_error(ImportError, /has no "Closing Balance" column.*Its columns are:.*Balance/m)
      end

      # Missing every column is a different mistake — the wrong file entirely, or one with no header row —
      # and listing eight names would bury that rather than say it.
      it 'says the file is not this account\'s statement when nothing matches' do
        barclaycard = ImportTestHelpers.get_filename_with_path(lloyds_account).sub_ext('.wrong.csv')
        CSV.open(barclaycard, 'w') { |csv| csv << %w[Date Merchant Amount] << [ '06 Dec 24', 'Audible', '7.99' ] }

        begin
          expect { FileImporter.new(barclaycard, lloyds_account).import }
            .to raise_error(ImportError, /does not look like a statement for Lloyds Account.*none of the columns/m)
        ensure
          FileUtils.rm_f(barclaycard)
        end
      end

      it 'names a date the format cannot read' do
        ImportColumnsDefinition.find_by(account_id: lloyds_account.id).update!(date_format: "%Y-%m-%d")

        expect { FileImporter.new(lloyds_filename, lloyds_account).import }
          .to raise_error(ImportError, /is not a date in the format %Y-%m-%d/)
      end
    end
  end

  describe 'Barclaycard Import' do
    before(:all) do
      # Create Barclaycard test data
      @barclaycard_account = FactoryBot.create(:barclay_card_account)
      FactoryBot.create(:barclaycard_import_columns_definition)
      ImportTestHelpers.generate_test_file(@barclaycard_account)
    end

    after(:all) do
      ImportTestHelpers.cleanup_test_file(@barclaycard_account)
      Account.destroy_all
    end

    let(:barclaycard_account) { Account.find_by_name("Barclaycard") }
    let(:barclaycard_filename) { ImportTestHelpers.get_filename_with_path(barclaycard_account) }

    it 'has generated a suitable test file' do
      expect(File.exist?(barclaycard_filename)).to be true
    end

    describe 'imports the generated file correctly' do
      subject!(:file_importer) { FileImporter.new(barclaycard_filename, barclaycard_account).import }
      specify { expect(barclaycard_account.transactions.count).to eq(17) }
    end

    # This definition carries no balance column, so the key is date, description and amount alone and the
    # balance check cannot stand behind it.  It is the half of the pipeline where the skip logic is on its own.
    describe 'where the statement carries no balance' do
      it 'skips every row of a file already loaded' do
        FileImporter.new(barclaycard_filename, barclaycard_account).import

        expect { @second = FileImporter.new(barclaycard_filename, barclaycard_account).import }
          .not_to change(Transaction, :count)
        expect(@second).to have_attributes(imported: 0, skipped: 17)
      end

      # The example a Set in place of the tally would fail.  Two identical rows are a real statement shape —
      # two coffees from one shop on one day — and both belong in the account.
      it 'loads both of two genuinely identical rows' do
        row = FactoryBot.build(:transaction, account: barclaycard_account, date: Date.new(2024, 7, 16),
                                             trx_type: 'DEB', description: 'COFFEE',
                                             amount: Money.from_amount(-2.75))
        ImportTestHelpers.write_statement(barclaycard_account, [ row, row ])

        importer = FileImporter.new(barclaycard_filename, barclaycard_account).import

        expect(importer).to have_attributes(imported: 2, skipped: 0)
      end

      # ...and the other half of the same argument: where the account holds one of them already, exactly one
      # more should land, not none and not two.
      it 'loads only the copy the account is missing' do
        row = FactoryBot.build(:transaction, account: barclaycard_account, date: Date.new(2024, 7, 16),
                                             trx_type: 'DEB', description: 'COFFEE',
                                             amount: Money.from_amount(-2.75))
        ImportTestHelpers.write_statement(barclaycard_account, [ row ])
        FileImporter.new(barclaycard_filename, barclaycard_account).import

        ImportTestHelpers.write_statement(barclaycard_account, [ row, row ])
        importer = FileImporter.new(barclaycard_filename, barclaycard_account).import

        expect(importer).to have_attributes(imported: 1, skipped: 1)
        expect(barclaycard_account.transactions.where(description: 'COFFEE').count).to eq(2)
      end

      it 'derives the balances the file does not carry' do
        row = FactoryBot.build(:transaction, account: barclaycard_account, date: Date.new(2024, 7, 16),
                                             trx_type: 'DEB', description: 'COFFEE',
                                             amount: Money.from_amount(-2.75))
        ImportTestHelpers.write_statement(barclaycard_account, [ row ])

        FileImporter.new(barclaycard_filename, barclaycard_account).import

        imported = barclaycard_account.transactions.find_by(description: 'COFFEE')
        expect(imported.balance).to eq(barclaycard_account.opening_balance + imported.amount)
      end
    end
  end
end
