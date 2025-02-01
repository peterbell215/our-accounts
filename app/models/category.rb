# Class to represent a category of transactions that we want to group such as 'Utilities' or 'Regular Savings'.
# Categories are preloaded as part of the import process to the DB, but can then be managed and augmented.
class Category < ApplicationRecord
  has_many :transactions
  has_many :import_matchers

  validates :name, presence: true, uniqueness: true, length: { minimum: 3, maximum: 50 }
end