# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## The two other documents

Two documents cover the same ground as this file in more depth:

- **`design_docs/architecture.md`** — why the system is shaped the way it is: the domain model, both
  import forms and how they close the loop, the windowed transaction list, and the deliberate
  constraints.
- **`README.md`** — the user guide: the screens, how an account is set up, how statements are imported
  and categorised in practice, and what is not built yet.

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
providers, categorising the transactions, and analysing household expenditure. It is a household side
project, and the database is SQLite on local disk.

Everyone in the household signs in with their own password and their own authenticator app, and they all
see **the same** accounts, transactions and categories. That is authentication without multi-tenancy: no
table carries an owner, no query carries a scope, and `users` and `sessions` are the only two tables that
are not about money.

Rails 8.1 / Ruby 4.0.6, Hotwire (Turbo + Stimulus) with importmap, Propshaft, Pure-CSS (installed via
yarn into `node_modules`, which is added to the asset path in `config/initializers/assets.rb`). No JS
build step — do not introduce one.

**One feature calls out to the internet and the rest of the application does not.** `MergeSuggester` asks
the Claude API which counterparties are the same payee, through the `anthropic` gem; everything else reads
and writes the local database and nothing else. Keep it that way by default — a second outbound call is a
decision about where the household's data goes, not an implementation detail.

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

bin/kamal deploy                # deploy to accounts.peterbell.org.uk; see Deployment in architecture.md
bin/kamal logs                  # tail the running application
bin/kamal console               # rails console on the droplet
docker build -t our_accounts .  # build the production image locally, which CI does not do

bin/rails users:create                          # make someone who can sign in; prompts, never an argument
bin/rails users:list                            # who has a login, and whether two-factor is on
bin/rails "users:change_password[a@b.com]"      # a forgotten password
bin/rails "users:disable_totp[a@b.com]"         # a lost phone
```

There is deliberately no sign-up screen and no reset-by-email, so those four are the whole of user
administration — see **Authentication** below.

`db:seed` builds a whole account from the statement files in `db/`, via `AccountSeeder`: the account, its
`ImportColumnsDefinition`, the rules derived from the hand analysis (form A), the statement import
(form B), then the hand-assigned categories over the top. Every step is idempotent or skipped once done,
so it is safe to re-run. It runs in **development and production**, and does nothing in test.

The three strings identifying a real account — the account name and the two filenames — live in the
encrypted credentials under `seed_data` (`bin/rails credentials:edit`), so seeding needs
`config/master.key` and the statement files, both gitignored. Where any of that is absent it reports why
and does nothing, rather than failing, so a deploy does not fall over before the statements are in place.

### Worktrees do the work; merging happens in the main checkout

One topic per worktree, one session per worktree. **A session in a worktree finishes at the pull request:**
write the code, run the suite and RuboCop, keep the docs in step, commit, push the branch, open the PR.
Then stop, and say so — do not offer to merge it, and do not merge it if the PR turns out to be mergeable.

Merging is done from a session running in the main checkout, which is also where `main` is pulled, where
merged branches are deleted, and where anything touching the shared development database belongs. To tell
which kind of session this is:

```sh
test "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" && echo main checkout || echo worktree
```

The reason is that several worktrees are usually in flight at once. A worktree only knows its own branch,
so merging from one lands a change while the session holding the next one is unaware `main` has moved —
and rebasing, conflict resolution and CI all read more clearly from the checkout that owns `main`. Any
review of a branch (`/code-review`) is welcome from either kind of session; acting on `main` is not.

### Setting up a new worktree

`config/master.key` and `db/*.csv` are gitignored, so a new worktree has neither, and `db:seed` will
report that it cannot find them and do nothing — which reads like a broken seed the first time you meet
it. Symlink them from the main checkout rather than copying, so the real statements exist once on disk:

```sh
MAIN=$(dirname "$(git rev-parse --git-common-dir)")     # the main checkout, from any worktree
ln -sfn "$MAIN/config/master.key" config/master.key
for f in "$MAIN"/db/*.csv; do ln -sfn "$f" "db/$(basename "$f")"; done
```

Then `bin/rails db:prepare`, which creates `storage/development.sqlite3` **and runs the seed** — a
freshly created database is seeded automatically, so there is no need to call `db:seed` separately. The
worktree gets its own `storage/`, so none of this touches the main checkout's development database.

That own `storage/` means its own empty `users` table, so **run `bin/rails users:create` before starting
a server** or the sign-in screen is a dead end. The seed says so when it finds no users, rather than
seeding a default login: `db:prepare` runs it unattended on every fresh database, and a known password
created silently is not a thing to have in a household finance application. The symlinked
`config/master.key` carries the Active Record encryption keys with it, so nothing else is needed per
worktree.

Run `yarn install` as well, before starting a server. `node_modules` is gitignored, so a new worktree
does not have one, and `config/initializers/assets.rb` puts it on the asset path for the two Pure CSS
`@import`s at the top of `app/assets/stylesheets/application.css`. Without it Propshaft cannot resolve
those imports and says nothing about it: the pages still render, but with none of Pure underneath, so the
top menu falls back to a vertical list, the tables lose their styling and the action buttons look like
plain links. It reads like a stylesheet someone broke rather than a missing dependency. Propshaft also
caches its load path at boot, so installing into a worktree whose server is already running needs a
restart before the assets appear.

**`.dockerignore` excludes `db/*.csv` and `db/*.xlsx`, and must keep doing so.** Docker's build context
is the filesystem rather than git, so gitignoring them is not enough on its own — without the
`.dockerignore` entries the statements are baked into the image and pushed to the registry. Production
therefore has no source files to seed from, which is intended: it got its data by having a database
copied into place, not by seeding. See **Deployment** in `design_docs/architecture.md`.

Ruby is managed by rvm; `.ruby-version` selects `ruby-4.0.6`. Note that on Ruby 4.0 the `rack` gem must be
>= 3.2 — 3.1.x requires `cgi/cookie`, which Ruby 4 removed — and RuboCop must be >= ~1.89 to recognise
`4.0` in `.ruby-version`. Both are pinned accordingly in `Gemfile.lock`.

CI (`.github/workflows/ci.yml`) runs brakeman, importmap audit, rubocop and the full RSpec suite. The
`test` job runs the system specs headless against the Chrome the runner image already ships — it only
falls back to `apt-get` if the image has none, because installing it unconditionally reached Google's apt
repository on every run and hung three runs in a row. The job is capped at `timeout-minutes: 15` against a
suite that takes under two, so a wedged step fails in minutes rather than holding a runner for hours.
Screenshots from failures are uploaded as a build artifact.

`bin/brakeman` unshifts `--ensure-latest`, so the scan exits non-zero the moment a newer brakeman is
published, whatever it finds. A brakeman release on its own is enough to turn CI red until the gem is
bumped — that is a tooling problem, not a finding.

System specs use Capybara and need a real Chrome. The driver is `:selenium_chrome` locally so a failing
spec can be watched, and `:selenium_chrome_headless` when `ENV["CI"]` is set.

## Architecture

### Accounts are STI

`Account` is the base class with `BankAccount`, `CreditCardAccount` and `Counterparty` subclasses
(`type` column). A `Counterparty` is not one of the user's own accounts — it is a supplier or vendor
(e.g. "Octopus Energy"), and is what `Transaction#counterparty` points at. `AccountsController#index`
therefore filters to `BankAccount`/`CreditCardAccount` only.

`AccountsController` serves all three of `/accounts`, `/bank_accounts` and `/credit_card_accounts`
(see `config/routes.rb`), which is why `account_params` picks the permitted-params list and the wrapped
param key off the concrete class of `@account`. `Counterparty` deliberately does **not** go through it —
`account_params` returns `nil` for any other class, and the shared form and detail partial are about sort
codes and opening balances. Counterparties have their own `CounterpartiesController` and views.

`Account#transactions` is the `account_id` side only, so on a `Counterparty` it is always empty. The
counterparty side is `Account#counterparty_transactions` and `#counterparty_matchers`, both
`dependent: :nullify` — deleting a counterparty releases its transactions rather than deleting them, and a
rule with no counterparty still assigns its category.

### Authentication, in two steps

Built on the Rails 8 generator (`bin/rails generate authentication`) rather than on Devise or by hand:
its `Authentication` concern is the version-matched source of truth for the cookie details that are easy
to get subtly wrong. Its password-reset half — `PasswordsController`, `PasswordsMailer`, their views and
the `resources :passwords` route — was **deleted**, because no SMTP is configured in any environment and
an endpoint that silently emails nothing reads as a working feature.

**A `Session` row exists only for a fully authenticated sign-in.** This is the invariant the second
factor rests on, and the reason to be careful with anything near `start_new_session_for`.
`Authentication#resume_session` finds a user by `Session.find_by(id: cookies.signed[:session_id])` and by
nothing else, so a row written before the code has been checked *is* a way past the code — anyone who
abandons the redirect is already in. Between the two steps there is therefore nothing but
`session[:pending_user_id]` and `session[:pending_at]` in the Rails cookie, good for
`TotpChallengesController::WINDOW` and no longer. Exactly two places call `start_new_session_for`:
`SessionsController#create`, for someone with no second factor, and `TotpChallengesController#create`.

`User#totp_required?` is `otp_confirmed_at.present?`, and it is the only predicate the sign-in path
consults. A secret generated but never confirmed does not count — someone who opened the enrolment screen
and closed it again has no way to produce a code, and locking them out is the one failure this must not
have.

The TOTP secret is `encrypts`-ed. The keys come from the credentials, except in test, where
`config/environments/test.rb` spells out three of its own **because CI has no `config/master.key`**.
Encryption keys are read lazily rather than at boot, so without that the suite would pass everywhere
except CI, and only on the first example that writes one.

Three smaller things that look like they need attention and do not:

- **`/up` needs no exemption.** `Rails::HealthController` descends from `ActionController::Base`, not
  from `ApplicationController`, so `include Authentication` never reaches it. A request spec asserts it.
- **`filter_parameter_logging.rb` already covers everything** — `:passw` catches the password fields,
  `:otp` catches `otp_secret` and the `otp_code` parameter, `:email` catches `email_address`. It needs no
  additions, which is worth knowing before someone adds them.
- **`include Authentication` sits *below* `allow_browser`** in `ApplicationController`, not where the
  generator puts it. Declared first, the authentication filter runs first, and a browser too old for the
  application gets redirected to a sign-in screen it also cannot render.

**A background fetch gets 401, not a redirect.** `Authentication#request_authentication` answers
`head :unauthorized` with the sign-in URL in `WWW-Authenticate` for `request.xhr?` and Turbo Stream
requests. Without it the transaction list's paging fetch follows the 302 transparently, receives the
sign-in page as a 200, finds no rows in it and quietly decides it has reached the end of the history.
`@rails/request.js` already acts on that header — its `FetchRequest#perform` sends the browser to the URL
itself — so no JavaScript in this application had to learn about it.

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
rather than guessed at; and each rule gets a `Counterparty` named after its description, trimmed to the
50 characters `Account` allows. Those counterparty names are therefore raw statement text
("TESCO STORES 2889"), not tidy payee names — the counterparties screen sorts by name by default and can be
reordered by total spend, which is what brings the ones worth renaming to the top. `ImportMatcher.counterparty_id` is nullable, so a description too short to be a
name (`O2`) still gets its rule, reported through `counterparties_unnamed`. Skipped rows are reported, not
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
2. `FileImporter.new(path, account).import` parses the **whole file first**, then walks it calling
   `Transaction#find_match` → `Transaction#sequence` → `save!` for each row that is not already loaded.
   It returns `self`, carrying `rows_read`, `imported`, `skipped`, `categorised`, `uncategorised` and the
   period covered, in the manner of `AnalysisImporter`.
3. `ImportMatcher.find_match` walks the matchers for that account **in `in_match_order`** —
   `(description_is_regex, id)`, so a literal description beats a regex — and returns the first whose
   `description` (literal or regex, per `description_is_regex`) and optional `trx_type` match. A hit
   fills in `category_id`, `counterparty` and `import_matcher_id` on the transaction.

Three things about that loop are load-bearing and were added when the import got a screen:

- **The whole file is one `ActiveRecord::Base.transaction`.** Every row used to be its own `save!`, so a
  statement that stopped part-way left an account half loaded. All or nothing is what lets the screen
  promise a refused file changed nothing. `#sequence` reads back rows written earlier in the same loop,
  which works because they are the same connection's own uncommitted writes. A spec asserts `Transaction.count`
  is zero after a refusal, and it fails if the wrapper is removed.
- **Rows already loaded are skipped, counted as a multiset.** Before the loop, the account's transactions
  over the file's date range are `pluck`ed into a `Hash` of key → count; each matching row decrements the
  count and is skipped. Key is `[date, description, amount_pence]`, plus `balance_pence` where the layout
  has a `balance_column`. A tally rather than a `Set` because a statement legitimately repeats the same
  description and amount on the same day, and a file holding two identical rows against a database holding
  one must load exactly one.
- **The matchers are loaded once, not per row.** `ImportMatcher.find_match` takes an optional preloaded,
  `in_match_order` collection. Without it, it queried and instantiated every rule for every row — measured
  at 9.1s against a real 2,626-row statement versus 5.1s with it. Passing an array cannot leak a rule
  across accounts because `#match` re-checks `account_id`.

Quirks that live in this pipeline and are easy to break:

- **Mapped columns are checked against the file's headers before any of it is read as data.** This has to
  be an explicit check, because it does not fail loudly: the factory reads each mapped column straight off
  the row, a name the file lacks arrives as `nil`, and `nil.to_f` is `0.0`. A mis-mapped `balance_column`
  therefore used to report every balance as £0.00 and blame the account for not reconciling.
- **`*_column` fields are dual-purpose.** When `header` is true they hold CSV header names; when it is
  false they hold integer column indexes. `ImportColumnsDefinition` metaprograms an override for every
  attribute in `CSV_HEADERS` that casts the value to `Integer` when `header` is false. Access these
  through the reader methods, not `self[...]`, unless you deliberately want the raw value.
- **`CSV_HEADERS` is spelled out by hand and its order is load-bearing** — `#csv_header` maps it straight
  onto CSV columns, so it is the layout of every statement the app writes back out. Do not "simplify" it
  back to `attribute_names.grep(/_column\z/)`: that follows the table's *physical* column order, and Rails
  8.1's schema dumper sorts columns alphabetically, so the next migration would silently reorder every
  exported CSV. A spec asserts the list still matches the table's `_column` attributes as a set.
- **`ImportMatcher#trx_type` is normalised so blank becomes `nil`.** `nil` means "any transaction type";
  an empty string would be a rule requiring an empty type, which nothing has, so it would never fire — and
  an empty form field is exactly what would produce one.
- **A regex `description` is validated on save**, so a bad pattern is refused at the form rather than
  raising `RegexpError` part-way through a few thousand rows.
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
paper over — and the message names the row and both balances, because it is shown on the import screen.
Views list transactions `order(date: :desc, day_index: :desc)`.

**A transaction added by hand never runs `#sequence`**, so it carries null `day_index` *and* null
`balance`. While a statement was only ever loaded into an empty account neither could be met; the import
screen makes both reachable, so `#sequence` coalesces the missing `day_index` to 0 and **refuses** a
predecessor with no balance by name. The refusal matters more than it looks: `previous&.balance ||
opening_balance` reads as a sensible default but silently restarts the running total as though the
account were empty.

### The statement import screen

`StatementImportsController`, routed as `new`/`create` under `/accounts/:account_id/statement_imports` —
the operation is the noun, and nesting is what stops a file landing against the wrong account. One step
and atomic, so there is no preview and no uploaded file to keep alive between two requests; every failure
message can therefore open by saying nothing was imported. The upload is a plain multipart param read off
`tempfile.path`, as on the CSV analysis screen — ActiveStorage's engine is configured but has no tables
and is used nowhere. It rescues `ImportError` only, deliberately unlike `CsvAnalysesController`'s blanket
rescue: that one renders into a Turbo frame where an exception leaves the frame blank, this one redirects,
so Rails' error report is the better account of a genuine bug. **Import Statement** is drawn on the account
whatever state it is in, and `new` explains a missing `ImportColumnsDefinition` with a link to the screen
that fixes it — a vanishing button leaves nothing to click and no reason why.

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

That partial takes `transaction:`, `account:` and `categories:` as **locals** — it used to read `@account`
and `@categories` as well, which is how a local gets dropped. Every caller passes all three.

The counterparty cell is a text field backed by one shared `<datalist id="counterparty-names">`, written
through `Transaction#counterparty_name=` (a name, not an id). An unknown name is **confirmed, then created**:
the first save comes back marked and the row carries the offered name back in a hidden
`confirmed_counterparty_name`, so a second save creates the `Counterparty` — via `belongs_to` autosave, which
is why anything the record would reject (too short, or one of the household's own account names) has to be
refused on the `Transaction` instead. The datalist is rendered **once** in `accounts/show.html.erb` and must
not be added to `transactions/_rows.html.erb`, or every fetched page appends another element with the same
id; a save that creates a counterparty appends one `counterparties/_option` to it as a second stream.

**Nothing is ever written beneath a field.** `transactions_list_controller.js` measures one row's height and
applies it to all of them, so a row that grows breaks the scroll arithmetic. The cell therefore only marks
itself — **amber `field-pending`** where the row is offering to create a name, **red `field-error`** where the
name cannot be saved at all (`TransactionsHelper#counterparty_field_class`) — and the words go to
`#transaction-message`, an always-empty div rendered above the list in `accounts/show.html.erb`. Every create
and update replaces it, *including the ones that succeed*, which is what clears a message the reader has
answered. It cannot reuse `layouts/_notice`, whose containers exist only when a flash is set, so a stream
would have nothing to target on the first rejection.

The row's third action icon is a **link** to `import_matchers#new`, carrying the description, category and
counterparty in the query string so a rule can be made without retyping them. A link and not a second
submit on the row's form: creating a rule fails three ordinary ways (duplicate description, missing
category, uncompilable pattern) and a row that may not change its height has nowhere to report them, and an
`<a>` is not in `form.elements` so `transaction_row_controller` never sees it. `trx_type` is deliberately not
prefilled (`nil` means "any type"), the link is offered even where a rule already claims the row (an exact
rule beating a broad pattern is a documented thing to want), and it is withheld while a counterparty is
awaiting confirmation. `ImportMatchersController#new` reads the prefill with `permit` plus an
`ActionController::Parameters` check — `params.expect` raises on the absent key, which is the ordinary case,
and `?import_matcher=nonsense` arrives as a String.

Transaction rows are rendered as CSS div-tables (`app/assets/stylesheets/div-tables.css`), not `<table>`.
Every date the reader sees is formatted on the server by the `short_date` helper, as `1-Jan-23`
(`config/initializers/date_formats.rb`) — use it rather than adding another `strftime`. Date *fields*
stay native, so the browser draws them in its own locale.

### Every screen opens with a strip of actions

Every `show.html.erb` is `content_for :title`, then an `<h1>`, then `show_actions` (`ApplicationHelper`,
rendering `layouts/_show_actions`), then the record — the same opening as every index, new and edit screen.
`show_actions` draws **Back**, **Edit** and **Destroy**, with any model-specific buttons passed as a block
and rendered between Edit and Destroy — for an account those are **Import Statement** then **Manage Import
Rules**, importing first because it is the errand that brings you to an account most months. A new Show screen uses it rather than writing its own links; the
labels are those three words on every screen, so a spec can `click_button 'Destroy'` anywhere. The heading
names the record, so the record partials do not repeat it as a `Name:` field.

The confirmation text is the screen's own argument, because what a delete costs differs — an account takes
its transactions with it, a counterparty leaves them behind. Actions belonging to a *list* further down the
page stay with that list: `Add New Transaction` is on the transaction list, not in the account's strip.
`spec/system/show_actions_spec.rb` covers all five screens, and asserts by geometry that the strip is above
the data rather than only that its buttons exist.

**New and Edit screens have their own strip**, `form_actions` (rendering `layouts/_form_actions`), in the
same position — under the `<h1>`, above the form. It draws **Back** to the list and, on an Edit screen,
**Show** to the record; those bare words again, not per-model wording. There is no Destroy: a form offers
nothing to delete that its Show screen does not, and Save should not sit next to it. Nothing goes at the
foot of the page — that is what this replaced, and on the category edit screen, whose form is followed by
the regular-payments table, it put the way back off the bottom of the screen. `.form-actions` is a second
selector on the `.show-actions` rule in `application.css`; do **not** rename `.show-actions` to unify them,
because `show_actions_spec.rb` selects on it to assert what a Show screen holds.
`spec/system/form_actions_spec.rb` covers all ten screens, by geometry, the same way.

`import_matchers/index` uses `form_actions` as well: it is the only list reached from somewhere other than
the menu bar, so the only one with anywhere to go back to. Transaction rows are the exception to all of
this, because the row is the form — the controller renders Turbo Streams and there is no `edit` route.

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
  `write_statement(account, transactions)` writes an explicit list of transactions through the same
  `#build_csv_data` round-trip — the right fixture for the skip logic, where what matters is two rows
  deliberately identical or one balance tampered with, rather than a realistic history.
- **`AccountTrxDataGenerator` leaves `day_index` unset when emitting to the database**, so a spec that
  seeds that way and then imports rows on the same dates is exercising the hand-added-transaction path in
  `Transaction#sequence` whether it means to or not.
- `.github/prompts/rspec-system-test.md` documents the house template for new system specs.
- **Every request and system example is signed in before it runs**, by two `config.before` hooks in
  `spec/rails_helper.rb`, so a spec about anything else does not have to say so. A spec that is *about*
  signing in opts out with `signed_out: true` on its `describe`. `spec/support/authentication.rb` holds
  the helpers and is a plain module with no `RSpec.configure` in it — `rails_helper` requires
  `spec/support/**` *before* `rspec/rails`, so nothing there may touch `RSpec::Rails` at load time.
- **`config.before(type: :system) { driven_by(:chrome_en_gb) }` has to come first.** rspec-rails
  registers `driven_by(:selenium_chrome_headless) unless @driver` as an example-group hook of its own,
  and config-level hooks run before those — so without naming the driver here, the sign-in hook would
  establish a session and then have the browser swapped out from under it. Naming it also means the
  registered `:chrome_en_gb` driver is used at all: it never was before, so the `--lang=en-GB` switch
  never applied and `ENV["LANGUAGE"]` was doing the whole job of pinning the locale.
- **`click_button` does not wait for the page it asks for.** Both sign-in helpers assert on the page
  that follows before returning; without it the example's own first `visit` cancels the sign-in in
  flight, and the failure lands somewhere else entirely, intermittently.

## Known gaps

- **Recovery is a rake task, not printed recovery codes.** A locked-out household member cannot recover
  themselves; they need whoever has a terminal on the machine the database is on. That is the right trade
  while the machine is the user's own — codes cost a table, per-code hashing, a show-once screen, a
  consumption path and specs for all of it, to buy recovery without shell access. **The deploy has
  removed that premise** — the rake task is now reached with `kamal app exec` against a rented droplet,
  which needs the deploy credentials, a strictly larger privilege than a printed code, and held by one
  person — so this is the gap most likely to be worth closing next.
- **Nothing expires a session.** The cookie is `permanent`, and only signing out, changing a password, or
  deleting the row ends it. There is also no record of sign-ins beyond the `Session` rows themselves —
  no history of where an account has been used from.
- **An import cannot be undone, and shows no progress.** The statement import screen is one atomic step:
  a file either lands whole or not at all. Nothing reverses a file that loaded correctly but was the
  wrong one — that is a matter of deleting the rows by hand. A real 2,626-row statement takes about five
  seconds inside the request, with no indication on screen beyond the browser's own; a background job is
  the answer if that ever becomes uncomfortable, and `solid_queue` only runs in production today.
- **A missing period is undetectable where the statement carries no balance.** Skipping already-loaded
  rows is keyed on date, description and amount, plus the balance where the layout has one. For Lloyds
  the balance chain catches a gap on the first row. For a Barclaycard-style layout with no balance column
  there is nothing to catch it: statements loaded out of order, or with a month missing between them,
  produce derived balances wrong by a constant and nothing says so.
- **Prediction exists; analysis of the past barely does.** The monthly forecast answers what this month
  will cost and how much of it has already gone — `Forecast::Month`, the strategies beside it and the
  `forecast` screens. Looking backwards is almost entirely missing: no charts, no totals by category over
  a period, no comparison between one period and another, and no record of how past forecasts did beyond
  recomputing them a month at a time. The exception is `Category#counterparty_spend`, rendered on the
  category Show screen — who a category was spent with, all-time, largest first.
  `design_docs/architecture.md` carries the detail, including the gaps the forecast itself opened.
- **A hand-set payment frequency can outlive its payee.** `PaymentSchedule` names a payee the way
  `Forecast::RegularPayments` groups it (`counterparty_id || description`), so recategorising its
  transactions leaves the row with nothing to apply to. `#candidates` therefore runs over the union of the
  payees in the history and the payees it holds rulings for — otherwise the row would appear on no screen,
  and the only place able to withdraw it could not show it. Nothing prunes them, and nothing warns when the
  history has come to contradict a ruling. Note that `RuleApplication` is now a ready way to orphan one:
  a rule naming a counterparty assigns it to every row it claims, so a ruling held by *description* stops
  matching the payee the detector now groups by id.
- There is deliberately **no `bin/dev` or `Procfile.dev`**. With importmap and Propshaft there is no
  asset build to watch, and solid_queue only runs in production, so foreman would be supervising a
  single process — while costing the interactive debugger, since its stdout is not a TTY. Use
  `bin/rails server`. Reintroduce `bin/dev` if development ever gains a second process, such as
  `bin/jobs`.
- `data:create_sample_data` appends to whatever is already in the development database — its
  `Rake::Task["db:truncate_all"]` "clear out the database" step is missing an `.invoke` and so does
  nothing. Fixing that would make the task wipe the dev db, so it has been left alone deliberately.
- **Applying a rule backwards is `RuleApplication`**, invoked from `ImportMatchersController` rather than
  from a callback on `ImportMatcher`: `AnalysisImporter` creates a few hundred rules in one run against an
  already-imported account, so a callback would turn one rake task into a few hundred sweeps of the
  transactions table. It reuses `ImportMatcher#match` unchanged — it duck-types on `account_id`, `trx_type`
  and `description`, which a saved `Transaction` satisfies — and `update_all`, because `#sequence` must not
  run again. A rule naming no counterparty leaves the row's own alone, unlike `Transaction#find_match`.
- **Merging counterparties is `CounterpartyMerge`**, driven from the counterparties list. Three orderings in
  it are load-bearing and all fail silently if reversed: re-point `counterparty_id` on transactions and
  rules *before* destroying the losers, because `Account#counterparty_transactions` and
  `#counterparty_matchers` are `dependent: :nullify`; move the losers' `PaymentSchedule` rows *before* too,
  for the opposite reason — `#counterparty_payment_schedules` is `dependent: :destroy`, so they would be
  deleted rather than nullified; and rename the survivor *after*, because the wanted name is usually held by
  a member of the set and `Account` validates name uniqueness across the whole STI table. Note that the
  schedules cannot go through the same `update_all` as the other two: the partial unique index on
  `(category_id, counterparty_id)` collides where the survivor is already ruled on in that category, so
  those are deleted first and the survivor's own ruling wins. Specs cover all three, confirmed to fail when
  the order is inverted.
- **Suggesting which counterparties to merge is `MergeSuggester`**, the one place anything leaves the
  machine. Four string heuristics were measured against the real names first and only stripping digits and
  punctuation was safe; the rest filed unrelated pubs under `THE` and treated `LNK`, `SQ *` and `PAYPAL` as
  payees when they are payment rails — which is a fact about what the words mean, so it asks the Claude API
  instead. It **proposes only**: each group is a link into the existing confirmation, and `CounterpartyMerge`
  runs unchanged over a set a person approved. The request carries counterparty names and their rules'
  category names and nothing else — no amounts, no dates, no account numbers — and a spec asserts that, so
  widening it is a deliberate act.

  **Which provider it talks to is configuration, not code**, because no API keys are issued here: development
  signs in with the Claude Code CLI and production goes through a third-party service. Three ways in, tried
  in that order, with configured credentials beating the ambient environment:

  1. `anthropic.api_key` in the credentials — sent as `x-api-key`. Unused under the current policy.
  2. `anthropic.auth_token`, with `base_url` and `model` — a bare `Authorization: Bearer`, which is what
     DigitalOcean and other Messages-API gateways want. This is the production path.
  3. `CLAUDE_CODE_OAUTH_TOKEN` in the environment, written by `claude setup-token` — the development path.

  **A Claude Code sign-in only reaches Haiku 4.5, and this was measured rather than assumed.** Against a
  real token, Opus 5, Opus 4.8 and Sonnet 5 all answer `429 rate_limit_error` with the message `"Error"`
  and **no `anthropic-ratelimit-*` headers at all**, while Haiku 4.5 answers normally. That is a tier
  boundary, not throttling: the 429 carries `x-should-retry: true`, but nothing is being replenished, so
  waiting never clears it. The default model therefore travels *with* the credential — `OAUTH_MODEL` for a
  sign-in, `MODEL` for a configured one — because choosing the credential and defaulting the model
  separately is exactly how development ends up asking for a model it cannot have. `ANTHROPIC_MODEL`
  overrides either, the environment being where development configures everything.

  Note that development and production therefore run **different models** on the same prompt, so a
  suggestion seen locally is not the one the deployed copy would make.

  **The OAuth token is not passed as `auth_token:`, and that is not a detail.** An OAuth token is only
  accepted alongside `anthropic-beta: oauth-2025-04-20`, and the SDK attaches that header on exactly one
  path: where the credential is an access-token *provider* rather than a bare token (`client.rb#auth_headers`
  — `@api_key`, then `@auth_token`, then `@token_cache`). So it is wrapped in
  `Anthropic::Credentials::StaticToken`, which routes through the token cache. Passed as `auth_token:` it
  would go out as a bearer with no beta header and come back 401.

  Put the production settings in `config/credentials/production.yml.enc`, not the shared credentials file:
  `credentials.yml.enc` is committed and readable in every environment, so a gateway token left there would
  have development spending the production budget. **Model ids are provider-specific** — the same model is
  `claude-opus-5` first-party and `anthropic-claude-opus-5` on DigitalOcean (`https://inference.do-ai.run`),
  and sending one provider's id to the other is a bare 404. Nothing configured at all is the state a fresh
  checkout is in, and the screen says so rather than failing.

  Specs that touch this **must pin `CLAUDE_CODE_OAUTH_TOKEN`**, including to `nil`. It is exported on the
  machines this is developed on, so an unpinned example reads a real token, builds a real client and makes a
  real network call from the suite — confirmed by removing the pin and watching a 401 come back from
  `api.anthropic.com`.

  Note `output_config: { format_: ... }` — the Ruby SDK spells that attribute with a trailing underscore
  (`api_name: :format`, as with `system_`), and passing `format:` sends no schema at all and returns prose.
  Structured outputs is undocumented on DigitalOcean, though tool calling is; if a gateway rejects
  `output_config`, the portable shape is one forced tool call with `SCHEMA` as its `input_schema`.
- **A merged-away counterparty can be resurrected.** `AnalysisImporter#counterparty_for` looks one up by
  name and creates it when absent, so re-running the analysis import recreates a name that was merged away,
  for any description that does not already have a rule; the guard skipping descriptions the account already
  has a rule for is what limits it. Confirming the old name in a transaction row does the same, though
  deliberately. Fixing either properly needs an "absorbed into" pointer and a schema change.
- **A rule only ever claims more, never fewer.** `RuleApplication` runs from `ImportMatchersController` on
  create and update, and takes only transactions where `import_matcher_id` *and* `category_id` are both
  null — hand judgement wins, so a rule's **Matched** count can read one lower than the number of
  transactions sharing its description. Nothing de-applies: narrowing or deleting a rule leaves the rows it
  claimed pointing at it, and a literal rule created after a regex one does not take that rule's rows. There
  is no preview of what a rule would catch before it is saved.
- **A hand edit through the transaction row does not clear `import_matcher_id`.** `transaction_params`
  permits `category_id` and nothing nulls the matcher, so a row whose category was corrected by hand still
  points at the rule that got it wrong. Nothing depends on it — `RuleApplication` reads the category, not the
  matcher — but "which rule categorised this" is only approximately true.
- `TransactionPresenter` is now **entirely unreferenced**. It was instantiated once in
  `transactions/_transaction_as_row.html.erb` and its return value never used; that line is gone, so the
  class is dead code kept only because deleting it was outside the change that orphaned it.
