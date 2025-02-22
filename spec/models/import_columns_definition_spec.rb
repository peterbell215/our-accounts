require 'rails_helper'

RSpec.describe ImportColumnsDefinition, type: :model do
  describe "factory" do
    subject(:lloyds_defs) { FactoryBot.create(:lloyds_import_columns_definition) }

    specify { expect(lloyds_defs.date_column).to eq 0 }
    specify { expect(lloyds_defs.date_format). to eq "%d/%m/%Y" }
  end

  describe '#build_csv_data generates the csv_data' do
    subject(:import_columns_definition) { FactoryBot.create(:lloyds_import_columns_definition) }

    let(:trx) { FactoryBot.build(:bertaux_transaction_for_export) }
    let(:csv_data) { import_columns_definition.build_csv_data(trx) }

    specify("date") { expect(csv_data[0]).to eq "12/12/2024" }
    specify("trx_type") { expect(csv_data[1]).to eq "DEB" }
    specify("sortcode") { expect(csv_data[2]).to eq "'30-00-00" }
    specify("account") { expect(csv_data[3]).to eq "01234567" }
    specify("description") { expect(csv_data[4]).to eq "Maison Bertaux" }
    specify("amount") { expect(csv_data[5]).to eq 5.95 }
    specify("credit") { expect(csv_data[6]).to be_nil }
    specify("balance") { expect(csv_data[7]).to eq 1525.80 }
  end
end
