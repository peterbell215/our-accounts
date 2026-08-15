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

    if importer.unusable.any?
      puts "\nSkipped #{importer.unusable.count} descriptions too short to name a counterparty:"
      importer.unusable.each { |description| puts "  #{description.inspect}" }
    end
  end
end
