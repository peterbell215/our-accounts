require 'rails_helper'

RSpec.describe "StatementImports", type: :request do
  let(:account) { Account.find_by(name: "Lloyds Account") || create(:lloyds_account) }
  let(:statement) { ImportTestHelpers.get_filename_with_path(account) }

  def upload(path, type: "text/csv")
    Rack::Test::UploadedFile.new(path, type)
  end

  describe "GET /accounts/:account_id/statement_imports/new" do
    context "when the account has a column layout" do
      before { create(:lloyds_import_columns_definition, account: account) }

      it "offers the upload, and says what loading a statement will and will not do" do
        get new_account_statement_import_path(account)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("csv_file")
        expect(response.body).to include("skipped")
        expect(response.body).to include("nothing at all is")
      end

      it "shows the layout the file will be read against" do
        get new_account_statement_import_path(account)

        expect(response.body).to include("Transaction Description")
      end
    end

    # The button on the account screen is drawn whatever state the account is in, so this screen is where a
    # missing layout has to be explained — and it is one link from being fixed.
    context "when the account has no column layout" do
      it "explains why it cannot import, and links to the screen that fixes it" do
        get new_account_statement_import_path(account)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("has no column layout yet")
        expect(response.body).to include(new_import_columns_definition_path)
      end
    end
  end

  describe "POST /accounts/:account_id/statement_imports" do
    before do
      create(:lloyds_import_columns_definition, account: account)
      ImportTestHelpers.generate_test_file(account)
    end

    after { ImportTestHelpers.cleanup_test_file(account) }

    it "loads the statement and says what landed" do
      expect { post account_statement_imports_path(account), params: { csv_file: upload(statement) } }
        .to change(Transaction, :count).by(17)

      expect(response).to redirect_to(account_path(account))
      expect(flash[:notice]).to match(/Imported 17 transactions into Lloyds Account/)
      expect(flash[:notice]).to match(/categorised by rule/)
    end

    it "skips what is already loaded and says so" do
      post account_statement_imports_path(account), params: { csv_file: upload(statement) }

      expect { post account_statement_imports_path(account), params: { csv_file: upload(statement) } }
        .not_to change(Transaction, :count)

      expect(flash[:notice]).to match(/All 17 rows in that file are already loaded/)
    end

    it "refuses a file that does not reconcile, importing none of it" do
      account.update!(opening_balance: Money.from_amount(999.99))

      expect { post account_statement_imports_path(account), params: { csv_file: upload(statement) } }
        .not_to change(Transaction, :count)

      expect(response).to redirect_to(new_account_statement_import_path(account))
      expect(flash[:alert]).to start_with("Nothing was imported.")
      expect(flash[:alert]).to match(/the statement says the balance is/)
    end

    it "asks for a file when none was chosen" do
      post account_statement_imports_path(account)

      expect(flash[:alert]).to eq("Choose a CSV file to import.")
    end

    it "refuses a file that is not a CSV" do
      not_csv = Rails.root.join('tmp', 'not-a-statement.txt')
      File.write(not_csv, "this is not a statement")

      begin
        expect { post account_statement_imports_path(account), params: { csv_file: upload(not_csv, type: "text/plain") } }
          .not_to change(Transaction, :count)

        expect(flash[:alert]).to match(/not a CSV/)
      ensure
        FileUtils.rm_f(not_csv)
      end
    end
  end

  describe "POST when the account has no column layout" do
    it "refuses rather than failing on the missing layout" do
      post account_statement_imports_path(account)

      expect(response).to redirect_to(new_account_statement_import_path(account))
      expect(flash[:alert]).to match(/has no column layout yet/)
    end
  end
end
