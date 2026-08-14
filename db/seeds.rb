require 'rake'

# Load the tasks into Rails - needed to seed the ```categories``` table.
Rails.application.load_tasks

# Setup the Categories.  The source spreadsheet holds real account data and is deliberately kept out of
# the repository (see /db/*.csv in .gitignore), so it will not be present on a fresh clone or in CI.
CATEGORY_SOURCE = 'outgoings-analysis-apr-to-jun24.csv'.freeze

if File.exist?(Rails.root.join('db', CATEGORY_SOURCE))
  Category.destroy_all
  Rake::Task['import:extract_categories'].execute(input_file: CATEGORY_SOURCE)
else
  puts "Skipping category seeding: db/#{CATEGORY_SOURCE} is not present."
end
