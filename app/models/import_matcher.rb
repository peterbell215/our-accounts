class ImportMatcher < ApplicationRecord
  belongs_to :account

  def match(imported_transaction)
    return false if self.account_id != imported_transaction.import_account_id
    return false if self.trx_type != nil && self.trx_type != imported_transaction.trx_type

    if self.description_is_regex
      return false if Regexp.new(self.description) !~ imported_transaction.description
    else
      return false if self.description != imported_transaction.description
    end

    return true
  end
end
