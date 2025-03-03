require 'rails_helper'

RSpec.describe ImportColumnsDefinition, type: :model do
  describe "factory" do
    subject(:lloyds_defs) { FactoryBot.create(:lloyds_import_columns_definition) }

    specify { expect(lloyds_defs.date_column).to eq "Transaction Date" }
    specify { expect(lloyds_defs.date_format). to eq "%d/%m/%Y" }
  end

  describe "Creating a record" do
    context "when the CSV file being imported includes a header row" do
      subject(:lloyds_defs) { FactoryBot.create(:lloyds_import_columns_definition) }

      specify { expect(lloyds_defs.date_column).to be_a String }
      specify { expect(lloyds_defs.date_column).to eq "Transaction Date" }
    end

    context "when the CSV file being imported does not include a header row" do
      subject(:barclaycard_defs) { FactoryBot.create(:barclaycard_import_columns_definition) }

      specify { expect(barclaycard_defs.date_column).to be_a Integer }
      specify { expect(barclaycard_defs.date_column).to eq 0 }
    end
  end

  describe '#build_csv_data generates the csv_data' do
    subject(:import_columns_definition) { FactoryBot.create(:lloyds_import_columns_definition) }

    let(:trx) { FactoryBot.build(:bertaux_transaction_for_export) }
    let(:csv_data) { import_columns_definition.build_csv_data(trx) }

    specify("date") { expect(csv_data["Transaction Date"]).to eq "12/12/2024" }
    specify("trx_type") { expect(csv_data["Transaction Type"]).to eq "DEB" }
    specify("sortcode") { expect(csv_data["Sort Code"]).to eq "'30-00-00" }
    specify("account") { expect(csv_data["Account Number"]).to eq "01234567" }
    specify("description") { expect(csv_data["Transaction Description"]).to eq "Maison Bertaux" }
    specify("amount") { expect(csv_data["Debit Amount"]).to eq 5.95 }
    specify("credit") { expect(csv_data["Credit Amount"]).to be_nil }
    specify("balance") { expect(csv_data["Balance"]).to eq 1525.80 }
  end
end
