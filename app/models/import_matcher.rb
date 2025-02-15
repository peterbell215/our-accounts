# This class provides a method #match to check if an ImportedTransaction matches the criteria defined
# by ImportMatcher.  An ImportMatcher is always associated with a specific account.  It understands
# how a specific transaction, say a DD from Octopus Energy will look in the Lloyds Account import.
class ImportMatcher < ApplicationRecord
  belongs_to :account
  belongs_to :other_party, class_name: "Account"
  belongs_to :category

  # Provided with an `ImportedTransaction` object, try and find a match using the matchers held in the database.
  #
  # @param [ImportedTransaction] imported_transaction
  # @return [Symbol|ImportMatcher] returns either :no_match if no match can be found or a reference to the first
  #                                successful match
  def self.find_match(imported_transaction)
    ImportMatcher.where(account_id: imported_transaction.import_account_id).each do |matcher|
      if matcher.match(imported_transaction)
        return matcher
      end
    end

    :no_match
  end

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