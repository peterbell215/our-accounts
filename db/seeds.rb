require 'rake'

# Load the tasks into Rails - needed to seed the ```categories``` table.
Rails.application.load_tasks

# Setup the Categories
Category.destroy_all
Rake::Task['import:extract_categories'].execute(input_file: 'outgoings-analysis-apr-to-jun24.csv')
