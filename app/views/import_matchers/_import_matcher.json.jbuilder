json.extract! import_matcher, :id, :account_id, :description, :description_is_regex, :trx_type,
              :category_id, :counterparty_id, :amount_comparison, :amount_pence, :amount_currency,
              :created_at, :updated_at
json.url account_import_matcher_url(import_matcher.account, import_matcher, format: :json)
