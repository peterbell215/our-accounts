# encoding : utf-8

Money.locale_backend = :i18n

MoneyRails.configure do |config|
  # To set the default currency
  #
  config.default_currency = :gbp


  # Default ActiveRecord migration configuration values for columns:
  #
  config.amount_column = { prefix: "",           # column name prefix
                           postfix: "_pence",    # column name  postfix
                           column_name: nil,     # full column name (overrides prefix, postfix and accessor name)
                           type: :integer,       # column type
                           present: true,        # column will be created
                           null: false,          # other options will be treated as column options
                           default: 0
                         }
end
