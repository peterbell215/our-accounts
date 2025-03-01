# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'

# Require any support files.
Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?

# Add additional requires below this line. Rails is not loaded until this point!

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts e.to_s.strip
  exit 1
end

RSpec.configure do |config|
  # setup for factory bot
  config.include FactoryBot::Syntax::Methods

  config.before(:suite) do
    Rails.application.load_seed
  end

  config.before(:each) do
    DatabaseCleaner.start
    FactoryBot.rewind_sequences
  end

  config.append_after(:each) do
    DatabaseCleaner.clean
  end
end
