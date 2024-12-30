class ImportMatcher < ApplicationRecord
  belongs_to :account

  def self.match(account, other_party_name)
    ImportMatcher.find_by(account_id: account.id, other_party: other_party, other_party_is_regex: false)

  end
end
