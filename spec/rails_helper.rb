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

# Capybara configuration.
#
# The locale has to be pinned. The dateinlocale Stimulus controller deliberately formats dates using the
# *browser's* locale, so specs asserting on a rendered date otherwise depend on where they run: a UK
# machine renders "3 January 2023" while a GitHub runner defaults to en-US and renders "January 3, 2023".
#
# Chrome is visible locally, where watching a failing system spec is useful, and headless in CI where
# there is no display.
# Chrome on Linux takes navigator.language from the LANGUAGE environment variable, not from the --lang
# switch, and it inherits the environment of this process. Setting it here is what actually pins the
# locale; the switch and the preference below cover other platforms and the Accept-Language header.
ENV["LANGUAGE"] = "en_GB:en"

Capybara.register_driver :chrome_en_gb do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--lang=en-GB")
  options.add_preference("intl.accept_languages", "en-GB,en")
  options.add_argument("--headless=new") if ENV["CI"].present?

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.default_driver = :chrome_en_gb
