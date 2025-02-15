# An interim object that holds the key data extracted from the import file in a neutral format, that can then be
# sent to the relevant matchers for matching.
class ImportedTransaction
  include ActiveModel::Model
  include ActiveModel::Attributes

  attr_accessor :import_account

  # This helps to mimic the behaviour of an active record.  If we are assigning an id, then we use this to find
  # the actual record and load it.
  def import_account_id=(id)
    @import_account = Account.find(id)
  end

  def import_account_id
    import_account.id
  end

  attribute :date, :date
  attribute :description, :string
  attribute :trx_type, :string

  # Money amounts
  attr_accessor :amount, :balance
end