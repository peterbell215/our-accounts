require 'rails_helper'

RSpec.describe ImportColumnsDefinition, type: :model do
  describe "factory" do
    subject(:lloyds_defs) { FactoryBot.create(:lloyds_import_columns_definition) }

    specify { expect(lloyds_defs.date_column).to eq 0 }
    specify { expect(lloyds_defs.date_format). to eq "%d/%m/%Y" }
  end
end
