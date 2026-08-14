# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'

ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'

# Require any support files.
Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }
require 'rspec/rails'

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?

# Add additional requires below this line. Rails is not loaded until this point!
require "capybara/rails"
require "capybara/rspec"

require 'money-rails' # Add this line to require the gem
require 'action_view/helpers/number_helper'
require 'money-rails/helpers/action_view_extension'
require 'action_view/record_identifier'

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts e.to_s.strip
  exit 1
end

RSpec.configure do |config|
  # Reset the database before each test
  config.use_transactional_fixtures = true

  # setup for factory bot
  config.include FactoryBot::Syntax::Methods

  # Categories the specs depend on.  These used to arrive via Rails.application.load_seed, but db/seeds.rb
  # sources them from a CSV of real account data that is deliberately not in the repository, so the suite
  # could only run on a machine that happened to have that file.  Creating them here keeps the suite
  # self-contained and deterministic.
  config.before(:suite) do
    REQUIRED_CATEGORIES.each { |name| Category.find_or_create_by!(name: name) }
  end

  config.before(:each) do
    FactoryBot.rewind_sequences
  end

  config.include Rails.application.routes.url_helpers
end

# Categories referenced by the factories (:matched_transaction, the import matchers) and by
# spec/system/transactions_spec.rb.
REQUIRED_CATEGORIES = [ "Shopping", "Travel", "Utilities" ].freeze

# Capybara configuration.  Run a visible Chrome locally, where watching a failing system spec is useful,
# but headless in CI where there is no display.
Capybara.default_driver = ENV["CI"].present? ? :selenium_chrome_headless : :selenium_chrome
