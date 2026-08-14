# Goal

Your goal is to generate a new RSpec System Test.

# Environment

The tests use Capybara to check the user interface.

# Creating a new Rspec file to hold the system test.

IF the context contains a system rspec file, then use that to add the RSpec tests.  If not, create the spec file, use the following as the initial template:

```ruby
require 'rails_helper'

RSpec.describe 'Maintaing a new account', type: :system do
  # insert the tests here.
end
```

# Test data

If a banking account is needed use ```FactoryBot.create(:lloyds_bank)``` to create the test account.

If a set of transactions are needed use ```AccountTrxDataGenerator``` to generate the transactions.  Here is an example of how to use it:
```ruby
  before(:all) do
    lloyds_account = Account.find_by(name: "Lloyds Account")
    # You can specify a specific import columns definition factory if needed
    generator = AccountTrxDataGenerator.new(
      account: lloyds_account,
      import_columns_definition_factory: :lloyds_import_columns_definition # Optional parameter
    )
    generator.generate(output: :db)
  end
```

