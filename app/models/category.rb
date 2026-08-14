# Class to represent a category of transactions that we want to group such as 'Utilities' or 'Regular Savings'.
# Categories are preloaded as part of the import process to the DB, but can then be managed and augmented.
class Category < ApplicationRecord
  has_many :transactions
  has_many :import_matchers

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
