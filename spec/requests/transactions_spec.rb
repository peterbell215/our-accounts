require 'rails_helper'

RSpec.describe 'Transactions', type: :request do
  let(:account) { create(:lloyds_account) }

  def tx(date, day_index: 0)
    create(:transaction, account: account, date: date, day_index: day_index,
                         description: "TX #{date}", amount: Money.from_amount(-10.00))
  end

  describe 'GET /accounts/:account_id/transactions' do
    before { 6.downto(1) { |n| tx(Date.new(2024, 6, n)) } }

    it 'answers a bare fragment of rows, carrying the next page url' do
      get account_transactions_path(account, rows: 1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-rows", "data-next-url")
      expect(response.body).not_to include("<html")
    end

    it 'does not answer a Turbo Stream — the browser decides which rows to render' do
      get account_transactions_path(account, rows: 1)

      expect(response.body).not_to include("turbo-stream")
    end

    it 'resumes after the cursor it is given' do
      stub_const("TransactionPage::SIZE", 2)

      get account_transactions_path(account, rows: 1, before_date: "2024-06-05", before_day_index: 0,
                                             before_id: account.transactions.find_by(date: Date.new(2024, 6, 5)).id)

      expect(response.body).to include("TX 2024-06-04", "TX 2024-06-03")
      expect(response.body).not_to include("TX 2024-06-05", "TX 2024-06-02")
    end

    it 'honours the anchor, so a paged list stays within the window being read' do
      get account_transactions_path(account, rows: 1, as_of: "2024-06-03")

      expect(response.body).to include("TX 2024-06-03")
      expect(response.body).not_to include("TX 2024-06-04")
    end

    it 'leaves the next page url empty at the end of the history' do
      get account_transactions_path(account, rows: 1)

      expect(response.body).to include('data-next-url=""')
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

  # The row can only carry a border and a tooltip without changing its own height, so the words travel as a
  # second stream targeting a container outside the list.
  describe 'PATCH /accounts/:account_id/transactions/:id — the counterparty message' do
    let(:transaction) { tx(Date.new(2024, 6, 1)) }

    def patch_counterparty(name)
      patch account_transaction_path(account, transaction),
            params: { transaction: { counterparty_name: name } },
            as: :turbo_stream
    end

    it 'says in words that the name is not a counterparty yet' do
      patch_counterparty('Bristol Water')

      expect(response.body).to include('transaction-message')
      expect(response.body).to include('is not a counterparty yet')
      expect(response.body).to include('row-question')
    end

    it 'says why a name it cannot create was refused' do
      patch_counterparty(account.name)

      expect(response.body).to include('row-error')
      expect(response.body).to include('is one of your own accounts')
    end

    it 'clears the message on a save that succeeds' do
      counterparty = create(:counterparty, name: 'Bristol Water', account_number: '99')

      patch_counterparty('Bristol Water')

      expect(transaction.reload.counterparty).to eq counterparty
      expect(response.body).to include('transaction-message')
      expect(response.body).not_to include('row-question')
      expect(response.body).not_to include('row-error')
    end
  end
end
