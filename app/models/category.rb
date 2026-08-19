# Class to represent a category of transactions that we want to group such as 'Utilities' or 'Regular Savings'.
# Categories are preloaded as part of the import process to the DB, but can then be managed and augmented.
class Category < ApplicationRecord
  # A category a rule still assigns cannot go: import_matchers.category_id has a foreign key and the rule has
  # no meaning without it, so the delete is refused with an error the screen can show rather than raising
  # ActiveRecord::InvalidForeignKey out of the controller.  Transactions are only labelled with a category,
  # so they keep everything else and simply stop naming one — and being nullified explicitly, they no longer
  # leave transactions.category_id pointing at a row that has gone, which no foreign key would have caught.
  has_many :transactions, dependent: :nullify
  has_many :import_matchers, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true, length: { minimum: 3, maximum: 50 }

  # Imports category names from a CSV holding a "Category" column, such as the outgoings analysis
  # spreadsheet.  Files without that column, for example a raw bank statement, are ignored.
  #
  # Existing categories are left untouched rather than being recreated, so this is safe to run
  # repeatedly.  That matters because transactions and import matchers reference categories by id.
  #
  # @param [Pathname, String] file
  # @return [Integer] the number of categories created
  def self.import_from_csv(file)
    csv = begin
      CSV.read(file, headers: true)
    rescue CSV::MalformedCSVError
      return 0
    end

    return 0 unless csv.headers.include?("Category")

    csv.count do |row|
      name = row["Category"]
      # Excel de-marks a string with a leading single quote, which we strip.
      name = name[1..] if name&.start_with?("'")
      next false if name.blank?

      find_or_create_by!(name: name).previously_new_record?
    end
  end
end
