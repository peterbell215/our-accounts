require "csv"

# Form B of the import: loads a raw statement download as transaction history.
#
# Where AnalysisImporter learns rules from a spreadsheet that was categorised by hand, this one does the
# routine work — it walks a file the bank produced, builds a Transaction from each row per the account's
# ImportColumnsDefinition, categorises it against the rules form A derived, and chains the running balance.
#
# Three things here exist because this is now driven from a screen rather than from `bin/rails runner`.
#
# **The whole file is one database transaction.**  Every row used to be its own save, so a statement that
# stopped part-way left an account half loaded, with no record of where it got to — the outcome the README
# warned readers about rather than one the application prevented.  All or nothing is what lets the screen
# promise that a refused file changed nothing.  #sequence reads back rows written earlier in the same loop,
# which is safe because they are the same connection's own uncommitted writes.
#
# **Rows already loaded are skipped rather than duplicated.**  A statement is downloaded for a date range,
# and those ranges overlap: the natural way to catch up is to download the last two months and load them
# over whatever is already there.  That used to double the rows up until #sequence refused one on a balance
# it could no longer reconcile, so AccountSeeder guarded it by declining to import into an account holding
# anything at all.  Skipping belongs here, in the loop that can see one row at a time, rather than in a
# caller that can only see the file.
#
# **What was skipped is counted rather than inferred.**  The counters below are read back by the import
# screen and by the seed, in the manner of AnalysisImporter, so both report what happened instead of
# re-querying the account afterwards and guessing.
class FileImporter
  attr_reader :file, :account, :import_column_definitions,
              :rows_read, :imported, :skipped, :categorised, :uncategorised,
              :imported_from, :imported_to

  # Initialize the FileImporter
  # @param file [String, Pathname] the path to the file to import
  # @param account [Account] the account to import the file into
  def initialize(file, account)
    @file = file
    @account = account
    @import_column_definitions = ImportColumnsDefinition.find_by(account_id: account.id)
    @rows_read = 0
    @imported = 0
    @skipped = 0
    @categorised = 0
    @uncategorised = 0
  end

  # Run the file import process taking account of whether the CSV is in reverse date order.
  #
  # Parsing happens in full before anything is written.  Everything the factory can object to — a date the
  # format does not read, a column the file does not have, a statement for the wrong account — is therefore
  # settled while the account is still untouched, so those failures are refusals rather than rollbacks, and
  # each can name the line of the file it came from.  A few thousand unsaved records cost nothing.
  #
  # @raise [ImportError] where the file cannot be read, or does not reconcile against what is already loaded
  # @return [FileImporter] self, so the caller can read the counts back
  def import
    rows = parse
    @rows_read = rows.size
    return self if rows.empty?

    dates = rows.map { |_line, transaction| transaction.date }
    @file_from, @file_to = dates.min, dates.max

    ActiveRecord::Base.transaction do
      already_loaded = existing_row_counts
      matchers = account.import_matchers.in_match_order.to_a

      rows.each { |line, transaction| load_row(line, transaction, already_loaded, matchers) }
    end

    self
  end

  private

  # Every row of the file, as an unsaved Transaction, in the order it should be loaded.
  #
  # The pairing with a line number is what lets a failure point at the file rather than at a row count: with
  # `reversed` the loop runs backwards, so "the eighth row processed" would be the wrong thing to tell
  # anybody.  Line 1 is the header, where there is one.
  #
  # @return [Array<Array(Integer, Transaction)>]
  def parse
    csv_data = read_csv
    refuse_unmapped_columns(csv_data)
    first_data_line = import_column_definitions.header ? 2 : 1

    index_range = (0...csv_data.count)
    index = (import_column_definitions.reversed ? index_range.reverse_each : index_range.each)

    index.map do |i|
      line = first_data_line + i
      [ line, build_row(csv_data[i], line) ]
    end
  end

  # @return [CSV::Table, Array<Array>]
  def read_csv
    CSV.read(@file, headers: import_column_definitions.header)
  rescue CSV::MalformedCSVError => e
    raise ImportError, "that file could not be read as CSV: #{e.message}"
  end

  # Refuse a file that does not carry every column the layout maps, before any of it is read as data.
  #
  # This has to be an explicit check rather than something caught as it goes wrong, because most of it does
  # not go wrong loudly.  The factory reads each mapped column straight off the row, so a name the file does
  # not carry arrives as nil — and `nil.to_f` is 0.0.  A mis-mapped balance column therefore produced a
  # statement claiming every balance was zero, and the reader was told the account did not reconcile: true,
  # but an account of the symptom rather than the cause, and it pointed at the wrong screen to fix it.
  #
  # Only for a file with headers.  An index-based layout addresses columns by position, where "missing" is a
  # short row rather than an absent name, and there is no list of names to check against.
  #
  # @param [CSV::Table, Array<Array>] csv_data
  # @return [void]
  def refuse_unmapped_columns(csv_data)
    return unless import_column_definitions.header

    expected = import_column_definitions.csv_header
    headers = Array(csv_data.headers).compact
    missing = expected - headers
    return if missing.empty?

    # Missing *all* of them is a different mistake from missing one, and saying so is the difference between
    # a usable message and a wall of column names.  It means the file is not this account's statement at all
    # — most often a download from the other account, or one whose first line is a transaction rather than
    # column names, in which case what got read as headers is really the first row of data.
    if missing.size == expected.size
      raise ImportError, "that file does not look like a statement for #{account.name}: none of the columns " \
                         "its layout expects are in it.  Either it is a download from a different account, " \
                         "or it has no header row and the layout says it has."
    end

    raise ImportError, "that file has no #{missing.map(&:inspect).to_sentence} " \
                       "#{'column'.pluralize(missing.size)}, which #{account.name}'s layout expects.  " \
                       "Its columns are: #{headers.join(', ')}.  Correct the layout, or choose a " \
                       "different file."
  end

  # @param [CSV::Row, Array] csv_row
  # @param [Integer] line
  # @return [Transaction]
  def build_row(csv_row, line)
    ImportedTransactionFactory.build(csv_row, import_column_definitions)
  rescue ImportError => e
    raise ImportError, "line #{line}: #{e.message}"
  rescue Date::Error
    raise ImportError, "line #{line}: #{csv_row[import_column_definitions.date_column].inspect} is not a " \
                       "date in the format #{import_column_definitions.date_format} that #{account.name}'s " \
                       "column layout expects."
  end

  # How many of each distinct row the account already holds, over the range the file covers.
  #
  # A tally rather than a set, because a statement legitimately repeats the same description and amount on
  # the same day — two coffees from one shop — and a set would silently drop the second.  Consuming one from
  # the count per match means a file holding two identical rows against a database holding one loads exactly
  # one of them.
  #
  # Plucked rather than loaded: this is asked over a range that can span a year, and every row of it only
  # ever becomes a hash key.
  #
  # @return [Hash{Array => Integer}]
  def existing_row_counts
    counts = Hash.new(0)

    account.transactions.where(date: @file_from..@file_to)
           .pluck(:date, :description, :amount_pence, :balance_pence)
           .each { |row| counts[key(*row)] += 1 }

    counts
  end

  # What makes two rows the same row.
  #
  # The balance is part of it only where the statement carries one, and where it does it is what makes the
  # key trustworthy: a running balance cannot repeat within a day, the same property AnalysisCategoriser
  # relies on to tie a spreadsheet row to the transaction it refers to.  Where the provider sends no balance
  # — Barclaycard — date, description and amount are all there is, and the class comment says what that costs.
  #
  # Pence integers rather than Money, so the key hashes on plain values.
  #
  # @return [Array]
  def key(date, description, amount_pence, balance_pence)
    row = [ date, description, amount_pence ]
    row << balance_pence if import_column_definitions.balance_column
    row
  end

  # @param [Integer] line
  # @param [Transaction] transaction
  # @param [Hash{Array => Integer}] already_loaded
  # @param [Array<ImportMatcher>] matchers
  # @return [void]
  def load_row(line, transaction, already_loaded, matchers)
    row_key = key(transaction.date, transaction.description, transaction.amount_pence, transaction.balance_pence)

    if already_loaded[row_key].positive?
      already_loaded[row_key] -= 1
      @skipped += 1
      return
    end

    transaction.find_match(matchers)
    transaction.sequence
    transaction.save!

    @imported += 1
    transaction.category_id ? @categorised += 1 : @uncategorised += 1

    # The period reported is the one the rows that *landed* cover, not the one the file covers.  Catching up
    # means loading a file that mostly repeats what is already here, so the two are usually quite different:
    # "imported 40 transactions, 2-Jan-24 to 13-Dec-24" claims a year's worth for what was really five days.
    @imported_from = transaction.date if @imported_from.nil? || transaction.date < @imported_from
    @imported_to = transaction.date if @imported_to.nil? || transaction.date > @imported_to
  rescue ImportError => e
    raise ImportError, "line #{line}: #{e.message}"
  rescue ActiveRecord::RecordInvalid => e
    raise ImportError, "line #{line}: that row could not be saved — #{e.record.errors.full_messages.to_sentence}."
  end
end
