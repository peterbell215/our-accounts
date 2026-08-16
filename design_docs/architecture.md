# Architecture

## What the system is for

`our-accounts` imports statements from UK banks and credit-card providers, categorises the transactions,
and — eventually — analyses and predicts household expenditure. Analysis is the point of the exercise;
importing and categorising are what make it possible.

It is a single-user application. There is no authentication, no multi-tenancy, and no notion of an
account owner: the database *is* the household's accounts. SQLite on local disk is the store, which is
adequate for a few thousand transactions a year and keeps the whole thing to a directory that can be
copied.

Rails 8.1 on Ruby 4.0.6, Hotwire (Turbo and Stimulus) over importmap, Propshaft, and Pure-CSS installed
through yarn. There is deliberately no JavaScript build step; assets are served as written.

---

## The domain

Five tables carry the whole model.

```
        Account (STI)
        ├── BankAccount          ─┐
        ├── CreditCardAccount    ─┤  the household's own accounts
        └── TradingAccount       ─┘  counterparties (Tesco, Octopus Energy)
              ▲            ▲
              │            │ other_party
     account  │            │
        ┌─────┴────────────┴───────┐
        │       Transaction        │──── category ───▶ Category
        └──────────────────────────┘
                    ▲
                    │ import_matcher
        ┌───────────┴──────────────┐
        │      ImportMatcher       │──── category, other_party
        └──────────────────────────┘

        ImportColumnsDefinition ──── account
```

### Accounts are single-table inheritance

`Account` is the base class; `BankAccount`, `CreditCardAccount` and `TradingAccount` are subclasses
discriminated by a `type` column. The first two are the household's own accounts and differ only in
validation — a bank account requires a sort code in `nn-nn-nn` form and an eight-digit account number, a
credit card requires a sixteen-digit card number and has no sort code.

`TradingAccount` is the interesting one. It is **not** an account the household holds; it represents a
counterparty — Tesco, Octopus Energy, the water company. Modelling counterparties as accounts means a
transaction's `other_party` is just another `Account`, and a future double-entry view (money leaving one
account and arriving at another) needs no new concept. The cost is that `Account` now holds two quite
different kinds of row, which is why `AccountsController#index` filters to
`BankAccount`/`CreditCardAccount` — the counterparties would otherwise swamp the account list.

`AccountsController` serves `/accounts`, `/bank_accounts` and `/credit_card_accounts` from one class.
The subclass routes exist so that Rails' form helpers generate the right wrapped parameter key, which is
why `account_params` picks both the permitted-parameter list and the expected key off the concrete class
of `@account`.

### Money is never a float

Every monetary column is an integer number of pence plus a currency column (`amount_pence` /
`amount_currency`), exposed through money-rails' `monetize`. Models and specs deal in `Money` objects;
raw floats and pence integers do not appear in application code.

`config/initializers/money.rb` sets the default currency to GBP, the rounding mode to `ROUND_HALF_EVEN`,
and `no_cents_if_whole` to false so pence always show. The rounding mode and locale backend lines look
like boilerplate but are load-bearing: money 7 changed both defaults, so removing them as redundant
would silently alter how every amount rounds and formats.

### Transactions carry their own running balance

A `Transaction` has a date but no time, which is a problem when several transactions land on the same
day: statements have an order, and the running balance only reconciles if that order is preserved.
`day_index` is the tiebreaker. `Transaction#sequence` finds the preceding transaction — ordered by
`date` then `day_index` — sets `day_index` to disambiguate same-day rows, and derives `balance` from the
previous balance plus the amount.

Where the statement supplies its own balance, `sequence` compares the two and raises `ImportError` on a
mismatch rather than accepting either. That strictness is the system's main integrity check, and it has
already earned its place: an incorrect opening balance was caught on the first row of a 2,626-row import
rather than producing thousands of subtly wrong records.

Views list transactions `order(date: :desc, day_index: :desc)`.

---

## Importing: two distinct forms

The system reads two kinds of CSV. They look superficially similar — both are statement exports — but
they do opposite things, and conflating them is the easiest mistake to make here.

```
  Form A: bootstrap                        Form B: routine
  ────────────────                         ───────────────

  hand-analysed statement                  raw download from the bank
  (statement + Category column)            (no Category column)
            │                                        │
            ▼                                        ▼
     AnalysisImporter                          FileImporter
            │                                        │
            ├──▶ Category                            ▼
            ├──▶ TradingAccount            ImportedTransactionFactory
            └──▶ ImportMatcher  ──────────────▶  (find_match)
                                                     │
                                                     ▼
                                             Transaction#sequence
                                                     │
                                                     ▼
                                                 Transaction

  then, once transactions exist:
     AnalysisCategoriser ──▶ overwrites categories from the hand analysis
```

### Form A — bootstrap from previous analysis

Before the application existed, expenditure was categorised by hand in a spreadsheet. That spreadsheet is
an ordinary statement export with a `Category` column added by hand, and it is not history to be loaded —
it is **labelled training data**.

`AnalysisImporter` reads it and derives two things: the `Category` list, and one `ImportMatcher` rule per
distinct transaction description. Three judgement calls are baked in:

- **Rules are keyed on the description alone**, stored as a literal rather than a regex, with `trx_type`
  left unset so a rule is not tied to one transaction type.
- **A description filed under several categories takes the most frequent**, because the analysis was done
  by hand and the occasional slip is expected. An outright tie is skipped and reported rather than
  guessed at.
- **Each rule needs a counterparty**, because `ImportMatcher.other_party_id` is `NOT NULL`. The statement
  only gives us the description, so that is what the `TradingAccount` is named after, trimmed to the
  fifty characters `Account` permits. Those names are therefore raw statement text — `TESCO STORES 2889`
  rather than `Tesco` — and would want consolidating if `other_party` is ever surfaced in the UI.

The spreadsheet also turns out to consolidate several accounts — a current account, two credit cards and
a store card — so rows are filtered on the sort-code and account-number columns before rules are built.
Categories are global and are taken from the whole file; only the rules are account-specific.

### Form B — the routine import

`ImportColumnsDefinition` (one per account) records how a given institution's CSV maps onto a
`Transaction`: which column holds the date, the description, the debit and credit or a single signed
amount, the balance, and so on. `FileImporter` walks the file and, for each row, calls
`ImportedTransactionFactory.build` → `Transaction#find_match` → `Transaction#sequence` → `save!`.

`ImportMatcher.find_match` walks the matchers for that account and returns the first whose description
(literal or regex, per `description_is_regex`) and optional `trx_type` match. A hit fills in
`category_id`, `other_party` and `import_matcher_id`.

Four quirks live in this pipeline, all of them driven by what the banks actually emit:

- **`*_column` fields are dual-purpose.** When `header` is true they hold CSV header names; when false
  they hold integer column indexes. `ImportColumnsDefinition` metaprograms a reader for every attribute
  in `CSV_HEADERS` that casts to `Integer` when `header` is false.
- **`reversed`** means the file is in reverse date order, so `FileImporter` iterates backwards to keep
  running balances correct. Lloyds exports newest-first; Barclaycard does not.
- **`credit_sign`** (1 or −1) flips the sign for providers such as Barclaycard that report spending as a
  positive number.
- **Leading single quotes.** CSVs that have been through Excel prefix some fields with `'`;
  `ImportedTransactionFactory.strip_leading_quote` removes them, and
  `ImportColumnsDefinition#extract_data` re-adds them when writing CSV back out.

The amount source is exclusive: either a single `amount_column`, or *both* `credit_column` and
`debit_column`, enforced by a custom validation.

### Closing the loop

Rules generalise a category across every transaction sharing a description. That is a good approximation
— against the real data it agrees with 625 of 672 hand labels — but it loses two things: payees that
genuinely belong to different categories on different occasions, and the cases where the analysis was
split evenly and the importer declined to guess.

`AnalysisCategoriser` puts those judgements back, after the import, by matching analysis rows to
transactions on **date and running balance**. That pair is unique — a running balance cannot repeat
within a day — and it is reliable by construction, because `Transaction#sequence` has already verified
each imported balance against the same statement. Description and amount would not do: descriptions
repeat with the same amount on the same day.

### Seeding ties it together

`AccountSeeder` runs the whole chain in order — account, columns definition, rules, import, labels — and
is what `db/seeds.rb` calls. Each step is idempotent or skipped once done, so seeding can be re-run
against an existing database. It runs in development and production, and does nothing in test.

The account's opening balance is **derived from the statement** rather than configured: the raw download
is reverse-ordered, so the oldest transaction is the last row, and working back from its balance keeps
the account consistent with whatever statement is present. `Transaction#sequence` rejects it immediately
if it is wrong.

The three strings that identify a real account — the account name and the two filenames — live in the
encrypted credentials under `seed_data`, because the repository is public. The statement files themselves
are gitignored for the same reason.

---

## The web layer

Conventional Rails: seven controllers, ERB views, no client-side framework.

**Turbo Streams for transactions.** `TransactionsController` renders Turbo Stream responses exclusively
for index/new/create/update/destroy, all targeting one partial, `transactions/_transaction_as_row`. New
rows are inserted with `turbo_stream.before("end-of-table-marker", ...)`, and unsaved rows are addressed
by `dom_id(@transaction, "new")` — so the DOM ids in `accounts/show.html.erb` are part of the contract.

**The transaction list is windowed.** An account holds thousands of rows, so `TransactionPage` serves one
page at a time. It combines two ideas: an *anchor* date bounding the window, which the day/week/month
buttons move and which is clamped to the account's own range so navigation cannot strand the reader on an
empty list; and a *keyset cursor* — `(date, day_index, id)` — for paging, so that adding a transaction
mid-scroll neither repeats a row nor hides one. `day_index` is coalesced in both the ordering and the
cursor comparison, because rows added by hand through the UI never run `#sequence` and so have none.

Older pages load from the `transactions#index` action as the reader scrolls. The response is a Turbo
Stream that appends rows and swaps the end-of-table marker for one carrying the next cursor — rather than
the more usual nested lazy `<turbo-frame>` per page, because the list is a CSS `display: table` and its
rows have to remain direct children of the `table-row-group`. When the history runs out the replacement
marker carries no Stimulus controller, and the loading stops.

One trap worth recording: the query parameter is `as_of`, not `anchor`. Rails reserves `anchor:` in its
URL helpers for the fragment identifier, so `account_path(account, anchor: date)` silently produces
`/accounts/9#2024-06-05` and the value never reaches `params`.

**Four Stimulus controllers**, each small:

| Controller | Job |
| --- | --- |
| `dateinlocale` | Reformats ISO-8601 dates in data attributes to the browser's locale |
| `csv_analyzer` | Drag-and-drop of detected CSV columns into the definition form |
| `transaction_row` | Inline editing of a transaction row |
| `account` | Shows/hides the sort-code field by account type |

**The CSV analysis screen** is the one piece of real interaction design.
`ImportColumnsDefinition.analyze_csv` reads only the first rows of an uploaded sample and returns
`[headers, columns_data]`; `CsvAnalysesController#create` renders that as a partial; the `csv_analyzer`
controller lets the user drag detected header names or column indexes into the main form and toggles the
"has header" checkbox based on what the analysis found. It exists because writing an
`ImportColumnsDefinition` by hand against an unfamiliar bank export is tedious and error-prone.

Transaction rows are rendered as CSS div-tables (`div-tables.css`), not `<table>` elements.

---

## Testing

RSpec and FactoryBot, with a deliberate bias toward exercising the real pipeline rather than mocking it.

Factories are named after real institutions — `:lloyds_account`, `:barclay_card_account`,
`:lloyds_import_columns_definition`, `:barclaycard_import_columns_definition`. The Lloyds definition is
header-based and reversed; the Barclaycard one is index-based with `credit_sign: -1`. Between them they
cover both halves of the import logic, which is why changes to the pipeline should exercise both.

`AccountTrxDataGenerator` builds a realistic set of transactions for an account and can emit them either
to the database or to a CSV file formatted per that account's `ImportColumnsDefinition` — so the import
specs generate a statement, import it, and assert on the result, rather than checking a fixture. It is
also used by `data:create_sample_data`, so it is not test-only code.

The suite creates the categories it needs itself, via `REQUIRED_CATEGORIES` in `spec/rails_helper.rb`.
It deliberately does not seed from the real statement files: those are gitignored, so depending on them
would make the suite unrunnable on a fresh clone and in CI.

System specs drive a real Chrome through Capybara. The browser locale is pinned to `en_GB` via the
`LANGUAGE` environment variable, because the `dateinlocale` controller formats dates using the
*browser's* locale — without pinning, the same spec passes in the UK and fails on a US-defaulted CI
runner.

CI runs Brakeman, importmap audit, RuboCop and the full suite, with the system specs headless.

---

## Deliberate constraints

- **No JavaScript build step.** Importmap and Propshaft serve assets directly. Adding a bundler would
  buy nothing here and would cost the ability to edit a controller and reload.
- **No `bin/dev` or `Procfile.dev`.** With no asset build to watch and solid_queue running only in
  production, foreman would supervise a single process while costing the interactive debugger, whose
  stdout would no longer be a TTY. `bin/rails server` is the whole story. Worth revisiting if
  development ever gains a second process, such as `bin/jobs`.
- **The Gemfile pins the Ruby version** by reading `.ruby-version`, so a shell on the wrong Ruby fails
  with an explicit message rather than reporting the bundle's gems as missing.
- **Statement data never enters the repository.** `db/*.csv` is gitignored and the identifying strings
  live in encrypted credentials. Note that `.dockerignore` does *not* exclude `db/*.csv`, and Docker's
  build context is the filesystem rather than git — so a production image built locally would bake the
  statements in and push them to whatever registry Kamal targets. That needs settling before deploying.

---

## Where it stands

Working: the account model, both import forms, the categorisation rules and their per-transaction
corrections, the CSV analysis screen, transaction CRUD over Turbo, and seeding that rebuilds a
development database end to end.

The two gaps that matter:

- **Form B has no UI or route.** `FileImporter` is only ever invoked from `AccountSeeder` and from its
  spec. Loading a new statement means dropping into `bin/rails runner`. This is the obvious next piece of
  work, and it is now a much more attractive one, because the categorisation behind it is real: against
  a year's actual downloads, the derived rules categorise about 64% of transactions automatically, and
  85% within the window that was analysed by hand.
- **No analysis or prediction exists yet** — no reporting views, no aggregation by category or period.
  This is the point of the application and none of it is built.

Smaller ones: `TradingAccount` has no routes or views, so counterparties can only be created through the
console or by the import; the transactions table shows a hardcoded placeholder where `other_party` should
be; and the accounts index renders raw ISO dates while the show page renders localised ones.

Until form B gets a UI, the entry points are rake tasks — `import:analysis` to derive the rules,
`import:categorise` to apply the hand labels, and `db:seed` to run the whole chain through
`AccountSeeder`.
