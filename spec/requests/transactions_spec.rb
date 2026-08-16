require 'rails_helper'

RSpec.describe 'Transactions', type: :request do
  let(:account) { create(:lloyds_account) }

  def tx(date, day_index: 0)
    create(:transaction, account: account, date: date, day_index: day_index,
                         description: "TX #{date}", amount: Money.from_amount(-10.00))
  end

  describe 'GET /accounts/:account_id/transactions' do
    before { 6.downto(1) { |n| tx(Date.new(2024, 6, n)) } }

    it 'answers a Turbo Stream that appends rows and moves the end-of-table marker' do
      get account_transactions_path(account), headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="before"', 'action="replace"', 'end-of-table-marker')
    end

    it 'resumes after the cursor it is given' do
      stub_const("TransactionPage::SIZE", 2)

      get account_transactions_path(account, before_date: "2024-06-05", before_day_index: 0,
                                             before_id: account.transactions.find_by(date: Date.new(2024, 6, 5)).id),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.body).to include("TX 2024-06-04", "TX 2024-06-03")
      expect(response.body).not_to include("TX 2024-06-05", "TX 2024-06-02")
    end

    it 'honours the anchor, so a paged list stays within the window being read' do
      get account_transactions_path(account, as_of: "2024-06-03"),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.body).to include("TX 2024-06-03")
      expect(response.body).not_to include("TX 2024-06-04")
    end

    it 'redirects a plain browser request back to the account page' do
      get account_transactions_path(account, as_of: "2024-06-03")

      expect(response).to redirect_to(account_path(account, as_of: "2024-06-03"))
    end
  end

  describe 'GET /accounts/:id' do
    before { 3.downto(1) { |n| tx(Date.new(2024, 6, n)) } }

    it 'renders only the first page of transactions' do
      stub_const("TransactionPage::SIZE", 2)

      get account_path(account)

      expect(response.body).to include("TX 2024-06-03", "TX 2024-06-02")
      expect(response.body).not_to include("TX 2024-06-01")
    end

    it 'moves the window when given an anchor' do
      get account_path(account, as_of: "2024-06-02")

      expect(response.body).to include("TX 2024-06-02", "TX 2024-06-01")
      expect(response.body).not_to include("TX 2024-06-03")
    end
  end
end
