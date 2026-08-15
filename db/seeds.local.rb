# Rebuilds a development database end to end from the statement files in db/.
#
#   bin/rails runner db/seeds.local.rb
#
# Safe to re-run.  Each step is either idempotent or skipped when it has already been done, so this can
# be used to rebuild a development database from nothing or to top up an existing one.
#
# The account name and the two filenames identify a real account, so they live in the encrypted
# credentials rather than here:
#
#   bin/rails credentials:edit
#
#   local_setup:
#     account_name: <the Account to build>
#     raw_statement: <a raw download in db/>
#     analysis: <the hand-analysed spreadsheet in db/>
#
# The statement files themselves are gitignored, being real account data.

abort "Refusing to run outside development." unless Rails.env.development?

setup = Rails.application.credentials.local_setup
abort "No local_setup in the credentials. See the comment at the top of this file." if setup.blank?

ACCOUNT_NAME = setup.account_name
RAW_LLOYDS = setup.raw_statement
ANALYSIS = setup.analysis

%i[account_name raw_statement analysis].each do |key|
  abort "credentials local_setup.#{key} is not set." if setup[key].blank?
end

def path_to(filename)
  path = Rails.root.join("db", filename)
  abort "#{path} is missing. The statement files are gitignored, so copy them in first." unless File.exist?(path)
  path
end

# The raw download is in reverse date order, so the oldest transaction is the *last* row.  Deriving the
# opening balance from it rather than hardcoding a figure keeps the account consistent with whatever
# statement is actually present, and Transaction#sequence will reject it immediately if it is wrong.
# @return [Array(Date, Money, String, String)]
def opening_position(path)
  rows = CSV.read(path, headers: true)
  oldest = rows[rows.count - 1]

  amount = Money.from_amount(oldest["Credit Amount"].to_d - oldest["Debit Amount"].to_d)
  balance_after = Money.from_amount(oldest["Balance"].to_d)
  date = Date.strptime(oldest["Transaction Date"].strip, "%d/%m/%Y")

  [ date - 1, balance_after - amount,
    oldest["Sort Code"].to_s.delete_prefix("'"), oldest["Account Number"].to_s.delete_prefix("'") ]
end

raw = path_to(RAW_LLOYDS)
analysis = path_to(ANALYSIS)

# --- the account ------------------------------------------------------------------------------------
opening_date, opening_balance, sortcode, account_number = opening_position(raw)

account = BankAccount.find_or_initialize_by(name: ACCOUNT_NAME)
if account.new_record?
  account.update!(sortcode: sortcode, account_number: account_number,
                  opening_date: opening_date, opening_balance: opening_balance)
  puts "Created #{ACCOUNT_NAME}: opening #{opening_balance.format} on #{opening_date}"
else
  puts "#{ACCOUNT_NAME} already exists: opening #{account.opening_balance.format} on #{account.opening_date}"
end

# --- how its statements are laid out ----------------------------------------------------------------
definition = ImportColumnsDefinition.find_or_initialize_by(account: account)
definition.assign_attributes(
  header: true, reversed: true, credit_sign: 1,
  date_column: "Transaction Date", date_format: "%d/%m/%Y",
  trx_type_column: "Transaction Type",
  sortcode_column: "Sort Code", account_number_column: "Account Number",
  other_party_column: "Transaction Description",
  amount_column: nil, debit_column: "Debit Amount", credit_column: "Credit Amount",
  balance_column: "Balance"
)
if definition.new_record? || definition.changed?
  definition.save!
  puts "Import columns definition written."
else
  puts "Import columns definition already correct."
end

# --- form A: the rules, derived from the hand analysis -----------------------------------------------
importer = AnalysisImporter.new(analysis, account).import
puts "Rules: #{importer.matchers_created} created, #{ImportMatcher.where(account: account).count} in total " \
     "(#{importer.ambiguous.count} ambiguous and #{importer.unusable.count} unusable descriptions skipped)."

# --- form B: the transactions themselves -------------------------------------------------------------
# FileImporter is not idempotent; a second run would double up and Transaction#sequence would reject the
# balances, so only import into an empty account.
if account.transactions.any?
  puts "Transactions: #{account.transactions.count} already present, skipping the import."
else
  FileImporter.new(raw, account).import
  puts "Transactions: #{account.transactions.count} imported."
end

# --- the hand-assigned categories, over the top of the rules -----------------------------------------
result = AnalysisCategoriser.new(analysis, account).apply
puts "Labels: #{result.assigned} applied, #{result.corrected.count} correcting a rule, " \
     "#{result.unchanged} already right, #{result.not_found.count} unmatched."

categorised = account.transactions.where.not(category_id: nil).count
total = account.transactions.count
puts "\n#{ACCOUNT_NAME}: #{total} transactions, #{categorised} categorised (#{(100.0 * categorised / total).round(1)}%)."
