# Seeds the categories.
#
# Categories are derived from spreadsheets of real account data, which are deliberately kept out of the
# repository (see /db/*.csv in .gitignore).  Only files carrying a "Category" column contribute; raw
# statement exports are ignored.
#
# The test database is left alone.  The specs create the categories they need themselves, via
# REQUIRED_CATEGORIES in spec/rails_helper.rb, so that the suite does not depend on private data that is
# absent from a fresh clone and from CI.
#
# Note that this deliberately does not clear the categories first.  Transactions and import matchers
# reference categories by id, so destroying and recreating them would leave those rows pointing at
# categories that no longer exist.
if Rails.env.test?
  puts "Test environment: not seeding any data."
else
  sources = Rails.root.glob("db/*.csv")

  if sources.empty?
    puts "No CSV files found in db/, so there are no categories to import."
  else
    created = sources.sum { |file| Category.import_from_csv(file) }
    puts "Imported #{created} new categories from #{sources.count} CSV file(s). #{Category.count} in total."
  end
end
