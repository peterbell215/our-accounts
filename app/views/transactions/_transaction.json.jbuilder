json.extract! transaction, :id, :trx_date, :type, :creditor_id, :debitor_id, :created_at, :updated_at
json.url transaction_url(transaction, format: :json)
