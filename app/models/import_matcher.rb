# This class provides a method #match to check if an ImportedTransaction matches the criteria defined
# by ImportMatcher.  An ImportMatcher is always associated with a specific account.  It understands
# how a specific transaction, say a DD from Octopus Energy will look in the Lloyds Account import.
class ImportMatcher < ApplicationRecord
  belongs_to :account
  belongs_to :other_party, class_name: "Account"
  belongs_to :category

  # Tests whether the ```imported_transaction``` matches the criteria defined in the ```ImportMatcher```
  # @param [ImportedTransaction] imported_transaction
  def match(imported_transaction)
    return false if self.account_id != imported_transaction.import_account_id
    return false if self.trx_type != nil && self.trx_type != imported_transaction.trx_type

    if self.description_is_regex
      return false if Regexp.new(self.description) !~ imported_transaction.description
    else
      return false if self.description != imported_transaction.description
    end

    true
  end
end