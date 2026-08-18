# "Trading account" was never the word anyone used for these records; the screens have always called them
# counterparties, and the model now does too.  Three things carry the old name in the database: the STI
# discriminator, which holds the class name as a literal string, and the two foreign keys naming the role.
#
# The type update is raw SQL rather than through the model, so that renaming or reshaping Account later
# cannot change what this migration does when it is replayed.
class RenameTradingAccountToCounterparty < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE accounts SET type = 'Counterparty' WHERE type = 'TradingAccount'"

    rename_column :transactions, :other_party_id, :counterparty_id
    rename_column :import_matchers, :other_party_id, :counterparty_id
  end

  def down
    rename_column :transactions, :counterparty_id, :other_party_id
    rename_column :import_matchers, :counterparty_id, :other_party_id

    execute "UPDATE accounts SET type = 'TradingAccount' WHERE type = 'Counterparty'"
  end
end
