class AddAccountDateIndexToTransactions < ActiveRecord::Migration[8.1]
  def change
    # Transaction#sequence runs `account.transactions.where("date <= ?", date).order(:date, :day_index).last`
    # once for every row being imported, and there was no index on date at all — so a 2,626-row statement
    # scanned a growing table 2,626 times, at a cost growing with the square of the file.
    #
    # That was survivable while importing meant `bin/rails runner` and waiting.  It is not survivable inside
    # a web request, and this index is what makes the import screen possible at all.  Transaction.on_or_before,
    # behind every scroll of the transaction list, is the same query shape and gets the same benefit.
    #
    # index_transactions_on_account_id is now a strict prefix of this one and earns nothing it does not.
    # Dropping it is a separate argument, recorded in TODO.md rather than settled here.
    add_index :transactions, [ :account_id, :date ]
  end
end
