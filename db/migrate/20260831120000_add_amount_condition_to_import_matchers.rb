class AddAmountConditionToImportMatchers < ActiveRecord::Migration[8.1]
  def change
    # nil on both means "any amount", the same idiom trx_type already uses for "any type" — a rule can
    # therefore condition on the transaction amount as well as its description, or leave both blank and
    # act as the default for whatever a more specific, amount-conditioned rule does not catch.
    add_column :import_matchers, :amount_pence, :integer
    add_column :import_matchers, :amount_currency, :string
    add_column :import_matchers, :amount_comparison, :string
  end
end
