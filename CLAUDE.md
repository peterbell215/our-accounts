# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## The two other documents

Two documents cover the same ground as this file in more depth:

- **`design_docs/architecture.md`** — why the system is shaped the way it is: the domain model, both
  import forms and how they close the loop, the windowed transaction list, and the deliberate
  constraints.
- **`README.md`** — the user guide: the screens, how an account is set up, how statements are imported
  and categorised in practice, and the known broken parts (the Import Matcher screens).

### Read the relevant one first

Before starting work on anything either of them describes, read it rather than working from the summary
here — the architecture document before changing the import pipeline, the transaction/balance logic or
the transaction list; the README before changing anything user-facing. Where they disagree with this
file, they are the more detailed account; treat the discrepancy as something to fix rather than to pick
a side on.

### Keep them up to date, in the same change

Documenting a change is part of making it, not a follow-up task:

- **Any change to the system design goes in `design_docs/architecture.md`** — a new or removed model or
  table, a change to a relationship, a new stage or component in the import pipeline, a change to how
  balances or ordering work, a new page-level mechanism in the web layer, or a decision reversed. Record
  the *reason*, in the style of the document: what the alternative was and why it lost. Also update
  **Where it stands** when a gap listed there is closed or a new one opens.
- **Any change a user would notice goes in `README.md`** — a new or altered screen, a changed or renamed
  command, different behaviour on import or categorisation, a fixed or newly broken feature. Keep it in
  the user's language: no class names, no code.

Update the surrounding prose so the document still reads as one piece; do not append a changelog entry
or leave the old description standing next to the new one. A change that needs neither document does not
need an explanation — but say so in the summary if it is not obvious.

## What this app is

A personal finance tool ("our-accounts") for importing CSV statements from UK banks and credit-card
providers, categorising the transactions, and analysing household expenditure. It is a single-user side
project — there is no authentication, no multi-tenancy, and the database is SQLite on local disk.

Rails 8.1 / Ruby 4.0.6, Hotwire (Turbo + Stimulus) with importmap, Propshaft, Pure-CSS (installed via
yarn into `node_modules`, which is added to the asset path in `config/initializers/assets.rb`). No JS
build step — do not introduce one.

## Commands

Gems may not be installed in a fresh checkout — run `bundle install` (and `yarn install`) first.

```sh
bin/setup                       # install deps, prepare db, start server
bin/rails server                # dev server; there is no bin/dev, see the note below
bundle exec rspec               # full suite
bundle exec rspec spec/models/import_matcher_spec.rb          # one file
bundle exec rspec spec/models/transaction_spec.rb:42          # one example by line
bin/rubocop                     # lint (rubocop-rails-omakase)
bin/brakeman --no-pager         # security scan
bin/importmap audit             # JS dependency audit
bin/rails db:seed               # builds the account and its history from db/*.csv; no-op in test
bin/rails "import:analysis[outgoings-analysis-apr-to-jun24.csv,Lloyds Account]"   # form A, see below
bin/rails data:create_sample_data   # populate dev db with a Lloyds + Barclaycard account and transactions
```

`db:seed` builds a whole account from the statement files in `db/`, via `AccountSeeder`: the account, its
`ImportColumnsDefinition`, the rules derived from the hand analysis (form A), the statement import
(form B), then the hand-assigned categories over the top. Every step is idempotent or skipped once done,
so it is safe to re-run. It runs in **development and production**, and does nothing in test.

The three strings identifying a real account — the account name and the two filenames — live in the
encrypted credentials under `seed_data` (`bin/rails credentials:edit`), so seeding needs
`config/master.key` and the statement files, both gitignored. Where any of that is absent it reports why
and does nothing, rather than failing, so a deploy does not fall over before the statements are in place.

**Before deploying, note that `.dockerignore` does not exclude `db/*.csv`.** Docker's build context is
the filesystem rather than git, so those files are baked into the image and pushed to whatever registry
Kamal is configured with. Either exclude them and put the statements on the host, or satisfy yourself
that the registry is private.

Ruby is managed by rvm; `.ruby-version` selects `ruby-4.0.6`. Note that on Ruby 4.0 the `rack` gem must be
>= 3.2 — 3.1.x requires `cgi/cookie`, which Ruby 4 removed — and RuboCop must be >= ~1.89 to recognise
`4.0` in `.ruby-version`. Both are pinned accordingly in `Gemfile.lock`.

CI (`.github/workflows/ci.yml`) runs brakeman, importmap audit, rubocop and the full RSpec suite. The
`test` job installs Chrome and runs the system specs headless; screenshots from failures are uploaded as
a build artifact.

`bin/brakeman` unshifts `--ensure-latest`, so the scan exits non-zero the moment a newer brakeman is
published, whatever it finds. A brakeman release on its own is enough to turn CI red until the gem is
bumped — that is a tooling problem, not a finding.

System specs use Capybara and need a real Chrome. The driver is `:selenium_chrome` locally so a failing
spec can be watched, and `:selenium_chrome_headless` when `ENV["CI"]` is set.

## Architecture

### Accounts are STI

`Account` is the base class with `BankAccount`, `CreditCardAccount` and `TradingAccount` subclasses
(`type` column). A `TradingAccount` is not one of the user's accounts — it represents a counterparty
(e.g. "Octopus Energy") and is what `Transaction#other_party` points at. `AccountsController#index`
therefore filters to `BankAccount`/`CreditCardAccount` only.

`AccountsController` serves all three of `/accounts`, `/bank_accounts` and `/credit_card_accounts`
(see `config/routes.rb`), which is why `account_params` picks the permitted-params list and the wrapped
param key off the concrete class of `@account`.

### Money

Everything monetary goes through money-rails: integer `*_pence` columns plus a `*_currency` column,
exposed via `monetize`. Default currency GBP, rounding `ROUND_HALF_EVEN`, pence always shown
(`config/initializers/money.rb`). Always work with `Money` objects in models and specs
(`Money.from_amount(-63.50)`), never raw floats or pence integers.

The explicit `Money.rounding_mode` and `Money.locale_backend` lines in that initializer are load-bearing:
money 7 changed both defaults, so deleting them as redundant would quietly alter how every amount rounds
and formats. Formatting is also barely covered by the specs — only one asserts on a rendered amount — so
verify formatting changes by hand.

### Importing has two distinct forms

Do not conflate these. They read superficially similar CSVs but do opposite things.

**Form A — bootstrap from previous analysis.** Before the app existed, expenditure was categorised by
hand in a spreadsheet. `db/outgoings-analysis-apr-to-jun24.csv` is a Lloyds statement export for the
current account with a `Category` column added by hand. It is not a statement to be loaded as history;
it is *labelled training data*, used to derive the `Category` list and the `ImportMatcher` rules that
form B then relies on. Run once per analysis file, via `AnalysisImporter` / `import:analysis`.

`AnalysisImporter` keys one rule per distinct description, literal rather than regex, leaving `trx_type`
unset so a rule is not tied to one transaction type. Two judgement calls are worth knowing: a
description filed under several categories takes the **most frequent**, and an outright **tie is skipped**
rather than guessed at; and since `ImportMatcher.other_party_id` is `NOT NULL`, each rule gets a
`TradingAccount` named after its description, trimmed to the 50 characters `Account` allows. Those
counterparty names are therefore raw statement text ("TESCO STORES 2889"), not tidy payee names — worth
consolidating by hand if `other_party` ever gets surfaced in the UI. Skipped rows are reported, not
silently dropped, and the whole thing is idempotent.

**Form B — ongoing raw imports.** Raw downloads from the Lloyds and Barclaycard websites, with no
`Category` column, loaded as actual transactions and categorised automatically by the matchers form A
produced. This is the routine path, described below.

`db/` holds one example of each, which is a useful reference when working on either
(all three are gitignored, being real account data):

| File | Form | Shape |
| --- | --- | --- |
| `outgoings-analysis-apr-to-jun24.csv` | A | Lloyds columns **plus** a hand-added `Category` |
| `00370982_20240914_0712.csv` | B | raw Lloyds download, same columns, no `Category` |
| `statement_20250106220148.csv` | B | raw Barclaycard download, no header row, index-based |

### The import pipeline (form B)

This is the heart of the app. Reading `FileImporter`, `ImportColumnsDefinition` and
`ImportedTransactionFactory` together is the fastest way to understand it.

1. `ImportColumnsDefinition` (one per account) records how that institution's CSV maps onto a
   `Transaction`: which column holds the date, description, debit/credit or single amount, balance, etc.
2. `FileImporter.new(path, account).import` reads the CSV and, for each row, calls
   `ImportedTransactionFactory.build` → `Transaction#find_match` → `Transaction#sequence` → `save!`.
3. `ImportMatcher.find_match` walks the matchers for that account and returns the first whose
   `description` (literal or regex, per `description_is_regex`) and optional `trx_type` match. A hit
   fills in `category_id`, `other_party` and `import_matcher_id` on the transaction.

Quirks that live in this pipeline and are easy to break:

- **`*_column` fields are dual-purpose.** When `header` is true they hold CSV header names; when it is
  false they hold integer column indexes. `ImportColumnsDefinition` metaprograms an override for every
  attribute in `CSV_HEADERS` that casts the value to `Integer` when `header` is false. Access these
  through the reader methods, not `self[...]`, unless you deliberately want the raw value.
- **`reversed`** means the CSV is in reverse date order, so `FileImporter` iterates the rows backwards
  to keep running balances correct.
- **`credit_sign`** (1 or -1) flips the sign for providers such as Barclaycard that report spending as
  positive.
- **Leading single quotes.** CSVs exported via Excel prefix some fields with `'`;
  `ImportedTransactionFactory.strip_leading_quote` removes them and
  `ImportColumnsDefinition#extract_data` re-adds them when writing CSV back out.
- **Amount source is exclusive**: either `amount_column`, or *both* `credit_column` and `debit_column` —
  enforced by `validate_credit_debit_or_amount_column`.

### Transaction ordering and balances

`Transaction#sequence` is what makes a statement reconcile. It finds the preceding transaction (ordered
by `date`, then `day_index`), sets `day_index` to disambiguate same-day transactions, and derives
`balance` from the previous balance plus the amount. If the CSV supplied a balance that disagrees with
the calculated one it raises `ImportError` — that mismatch is a real data problem, not something to
paper over. Views list transactions `order(date: :desc, day_index: :desc)`.

### CSV analysis UI

`ImportColumnsDefinition.analyze_csv` reads just the first rows of an uploaded sample file and returns
`[headers, columns_data]`. `CsvAnalysesController#create` (routed as `POST /import_columns_definitions/analyze_csv`)
renders that as a partial; the `csv_analyzer` Stimulus controller lets the user drag the detected header
names / column indexes into the main `ImportColumnsDefinition` form and auto-toggles the "has header"
checkbox based on what the analysis found.

### Turbo usage

`TransactionsController` renders Turbo Stream responses exclusively for new/create/update/destroy,
targeting the `transactions/_transaction_as_row` partial. New rows are inserted with
`turbo_stream.before("end-of-table-marker", ...)`; unsaved rows are addressed by
`dom_id(@transaction, "new")`. Keep those DOM ids in sync with `app/views/accounts/show.html.erb`.

Transaction rows are rendered as CSS div-tables (`app/assets/stylesheets/div-tables.css`), not `<table>`.
Dates are emitted as ISO-8601 in data attributes and reformatted client-side to the browser locale by the
`dateinlocale` Stimulus controller.

## Testing conventions

- RSpec + FactoryBot; `config.include FactoryBot::Syntax::Methods`, so call `create(...)` directly.
- `spec/rails_helper.rb` creates the categories in its `REQUIRED_CATEGORIES` constant ("Shopping",
  "Travel", "Utilities") before the suite. The factories and `spec/system/transactions_spec.rb` look
  these up by name, so add to that constant rather than relying on seed data — `db/seeds.rb` builds from
  CSVs of real account data that are gitignored, and is a deliberate no-op under `RAILS_ENV=test` for
  exactly that reason.
- Factories are named after real institutions: `:lloyds_account`, `:barclay_card_account`,
  `:lloyds_import_columns_definition`, `:barclaycard_import_columns_definition`. The Lloyds definition
  is header-based and reversed; the Barclaycard one is index-based with `credit_sign: -1`. Between them
  they cover both halves of the import logic — when changing the pipeline, exercise both.
- `spec/support/account_trx_data_generator.rb` (`AccountTrxDataGenerator`) builds a realistic set of ~17
  transactions for an account and can emit them either to the database (`generate(output: :db)`) or to a
  CSV file (`generate(output: path)`) formatted per the account's `ImportColumnsDefinition`. It is also
  used by the `data:create_sample_data` rake task, so it is not test-only code.
- `ImportTestHelpers` wraps generating/cleaning up those CSV fixtures under `tmp/`.
- `.github/prompts/rspec-system-test.md` documents the house template for new system specs.

## Known gaps (the project stalled here)

- **There is no UI or route for running an import.** `FileImporter` is only ever invoked from
  `spec/models/file_importer_spec.rb`. Wiring it to a controller/upload form is the obvious next step.
- **No analysis or prediction features exist yet**, despite being the point of the app — no reporting
  views, no aggregation by category or period.
- There is deliberately **no `bin/dev` or `Procfile.dev`**. With importmap and Propshaft there is no
  asset build to watch, and solid_queue only runs in production, so foreman would be supervising a
  single process — while costing the interactive debugger, since its stdout is not a TTY. Use
  `bin/rails server`. Reintroduce `bin/dev` if development ever gains a second process, such as
  `bin/jobs`.
- `data:create_sample_data` appends to whatever is already in the development database — its
  `Rake::Task["db:truncate_all"]` "clear out the database" step is missing an `.invoke` and so does
  nothing. Fixing that would make the task wipe the dev db, so it has been left alone deliberately.
- The analysis file (form A) is the only import with a runnable entry point. **Form B has no UI or
  route** — see above.
- `TradingAccount` has no routes or views — counterparties can currently only be created in the console
  or via factories.
- `TransactionPresenter` is mostly gutted (its methods were moved into views) and is barely used.
