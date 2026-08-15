# Seeds an account and its history from the statement files in db/.
#
# AccountSeeder does the work: the account, its import columns definition, the categorisation rules
# derived from the hand-analysed spreadsheet, the statement import, and the hand-assigned categories
# applied over the top.  Every step is idempotent or skipped once done, so this is safe to re-run.
#
# It runs in development and in production, and does nothing in test.  The specs create the categories
# they need themselves, via REQUIRED_CATEGORIES in spec/rails_helper.rb, so that the suite does not
# depend on private data absent from a fresh clone and from CI.
#
# What it seeds from is named in the encrypted credentials, because those three strings identify a real
# account:
#
#   bin/rails credentials:edit
#
#   seed_data:
#     account_name: <the Account to build>
#     raw_statement: <a raw download in db/>
#     analysis: <the hand-analysed spreadsheet in db/>
#
# The statement files themselves are gitignored, being real account data.  Where any of this is absent,
# seeding reports why and does nothing, rather than failing: a deployment should not fall over because
# the statements have not been put in place yet.
if Rails.env.test?
  puts "Test environment: not seeding any data."
else
  seeder = AccountSeeder.from_credentials

  if seeder.nil? || !seeder.configured?
    puts "No seed_data in the credentials, so there is nothing to seed. See the comment in db/seeds.rb."
  elsif seeder.missing_sources.any?
    puts "Not seeding: #{seeder.missing_sources.join(', ')} #{seeder.missing_sources.one? ? 'is' : 'are'} missing."
  else
    seeder.seed
    account = seeder.account
    categorised = account.transactions.where.not(category_id: nil).count
    total = account.transactions.count

    puts "Account:      #{account.name}, opening #{account.opening_balance.format} on #{account.opening_date}"
    puts "Rules:        #{seeder.rules_created} created, #{ImportMatcher.where(account: account).count} in total"
    puts "Transactions: #{seeder.import_skipped ? "#{total} already present, import skipped" : "#{seeder.transactions_imported} imported"}"
    puts "Labels:       #{seeder.labels_applied} applied, of which #{seeder.labels_corrected} corrected a rule"
    puts "Categorised:  #{categorised} of #{total}#{" (#{(100.0 * categorised / total).round(1)}%)" if total.positive?}"
  end
end
