namespace :import do
  desc "Import categories from previous analysis data"
  task :extract_categories, [ :input_file ] => :environment do |_, args|
    created = Category.import_from_csv(Rails.root.join("db", args[:input_file]))
    puts "Created #{created} categories."
  end

  desc "Derive categories and import matcher rules from a hand-analysed statement"
  task :analysis, [ :input_file, :account_name ] => :environment do |_, args|
    abort "Usage: bin/rails \"import:analysis[file.csv,Account Name]\"" if args[:input_file].blank? || args[:account_name].blank?

    file = Rails.root.join("db", args[:input_file])
    abort "#{file} does not exist." unless File.exist?(file)

    account = Account.find_by(name: args[:account_name])
    abort "No account named #{args[:account_name].inspect}. Known: #{Account.order(:name).pluck(:name).join(', ')}" if account.nil?

    importer = AnalysisImporter.new(file, account).import

    puts "Categories created:      #{importer.categories_created} (taken from the whole file)"
    puts "Import matchers created: #{importer.matchers_created} against #{account.name}"
    puts "Rows for other accounts: #{importer.other_account_rows} (skipped)" if importer.other_account_rows.positive?

    if importer.ambiguous.any?
      puts "\nSkipped #{importer.ambiguous.count} descriptions filed under two categories equally often:"
      importer.ambiguous.each { |description, counts| puts "  #{description.squish.inspect} -> #{counts.inspect}" }
    end

    if importer.counterparties_unnamed.any?
      puts "\n#{importer.counterparties_unnamed.count} rules created without a counterparty, the description being too short to name one:"
      importer.counterparties_unnamed.each { |description| puts "  #{description.inspect}" }
    end
  end

  desc "Apply the hand-assigned categories from an analysis file to transactions already imported"
  task :categorise, [ :input_file, :account_name ] => :environment do |_, args|
    abort "Usage: bin/rails \"import:categorise[file.csv,Account Name]\"" if args[:input_file].blank? || args[:account_name].blank?

    file = Rails.root.join("db", args[:input_file])
    abort "#{file} does not exist." unless File.exist?(file)

    account = Account.find_by(name: args[:account_name])
    abort "No account named #{args[:account_name].inspect}." if account.nil?

    result = AnalysisCategoriser.new(file, account).apply

    puts "Categories applied:  #{result.assigned}"
    puts "Already correct:     #{result.unchanged}"
    puts "Corrected a rule:    #{result.corrected.count}"
    puts "No matching trx:     #{result.not_found.count}"

    if result.corrected.any?
      puts "\nWhere your analysis disagreed with the rules:"
      result.corrected.first(25).each { |description, was, now| puts "  #{description[0, 34].ljust(34)} #{was} -> #{now}" }
      puts "  ... and #{result.corrected.count - 25} more" if result.corrected.count > 25
    end

    if result.not_found.any?
      puts "\nAnalysis rows with no matching transaction (first 10):"
      result.not_found.first(10).each { |date, description, balance| puts "  #{date} #{description[0, 30].ljust(30)} #{balance}" }
    end
  end
end
