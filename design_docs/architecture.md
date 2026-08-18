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
        └── Counterparty         ─┘  counterparties (Tesco, Octopus Energy)
              ▲            ▲
              │            │ counterparty
     account  │            │
        ┌─────┴────────────┴───────┐
        │       Transaction        │──── category ───▶ Category
        └──────────────────────────┘
                    ▲
                    │ import_matcher
        ┌───────────┴──────────────┐
        │      ImportMatcher       │──── category, counterparty (optional)
        └──────────────────────────┘

        ImportColumnsDefinition ──── account
```

### Accounts are single-table inheritance

`Account` is the base class; `BankAccount`, `CreditCardAccount` and `Counterparty` are subclasses
discriminated by a `type` column. The first two are the household's own accounts and differ only in
validation — a bank account requires a sort code in `nn-nn-nn` form and an eight-digit account number, a
credit card requires a sixteen-digit card number and has no sort code.

`Counterparty` is the interesting one. It is **not** an account the household holds; it is a supplier or
vendor — Tesco, Octopus Energy, the water company. Modelling those as accounts means a transaction's
`counterparty` is just another `Account`, and a future double-entry view (money leaving one account and
arriving at another) needs no new concept. The cost is that `Account` now holds two quite
different kinds of row, which is why `AccountsController#index` filters to
`BankAccount`/`CreditCardAccount` — the counterparties would otherwise swamp the account list.

`AccountsController` serves `/accounts`, `/bank_accounts` and `/credit_card_accounts` from one class.
The subclass routes exist so that Rails' form helpers generate the right wrapped parameter key, which is
why `account_params` picks both the permitted-parameter list and the expected key off the concrete class
of `@account`.

`Counterparty` deliberately does **not** join that arrangement: it has its own `CounterpartiesController`
and views. Sharing would have meant a third branch in `account_params` (which returns `nil` for any other
class, so `update(nil)` would raise), hiding the sort-code, account-number, opening-date, opening-balance
and type fields in the shared form, and guarding `accounts/_account.html.erb` against the nil `opening_date`
a counterparty has. A counterparty is only a name, so a small separate controller is less code than bending
three shared views.

The reverse side of the association needed naming, too. `Account#transactions` is the `account_id` side, so on
a `Counterparty` it is always empty — a counterparty's dealings belong to the household's accounts, not to
it. `Account#counterparty_transactions` and `#counterparty_matchers` are the `counterparty_id` side, and both
are `dependent: :nullify`: deleting a counterparty must not delete the household's transactions, and a rule
with no counterparty still assigns its category. That also stopped `Account#destroy` tripping over the
foreign key on `transactions.counterparty_id`, which it previously did.

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
            ├──▶ Counterparty              ImportedTransactionFactory
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
- **A counterparty is derived where one can be named.** The statement only gives us the description, so
  that is what the `Counterparty` is named after, trimmed to the fifty characters `Account` permits.
  Those names are therefore raw statement text — `TESCO STORES 2889` rather than `Tesco` — which is why the
  counterparties screen can be ordered by total spend, which brings the ones worth renaming to the top. Where the
  description is too short to be a name at all (`O2`), the rule is still created with no counterparty and
  the description is reported. `ImportMatcher.counterparty_id` was `NOT NULL` until that changed, which is
  the only reason such a rule used to be discarded — its category was never in doubt.
- **Descriptions differing only in case share one counterparty**, and the spelling that is not shouted
  wins. The real statements write `TWO MAGPIES BAKERY` and `Two Magpies Bakery` for one bakery, twice on
  the same day in one instance, because the spelling comes from the card terminal rather than the bank. Two
  counterparties would split that vendor's page and total in half. Each spelling keeps its own rule, since
  a literal rule has to match the text as written, so both point at the one counterparty. Preferring the
  tidier spelling in that one direction only also keeps repeated runs from flip-flopping between them.

`Account#name` is squished on write and **case-insensitively unique**, which is what makes the above
compulsory rather than a nicety: a second spelling would fail validation and abort the import. The same
pair of rules serves the lookup that resolves a name typed into a transaction row, so both go through one
scope, `Account.named`.

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
`category_id`, `counterparty` and `import_matcher_id`.

**Rule precedence is explicit.** `find_match` orders by `in_match_order` — `(description_is_regex, id)` —
so a literal description beats a regex, and the outcome does not depend on what order the database happens
to return rows in. That went unnoticed for as long as every rule was a literal derived from the analysis
file; it became load-bearing the moment the UI let someone write a pattern by hand. `trx_type` is normalised
so blank becomes `nil`, because `nil` means "any type" and a rule demanding an empty string would silently
never fire — which is exactly what a form leaving the field empty would otherwise store. The regex is also
validated on save rather than being left to raise `RegexpError` part-way through a 2,600-row import.

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
against an existing database. `AnalysisImporter` therefore **skips a description this account already has a
rule for**, rather than reasserting the spreadsheet's category and counterparty over it: since the rules are
editable in the web layer, updating them here would make every re-seed silently revert corrections made by
hand. It counts those separately from the ones it created so the run still reports what it did. It runs in development and production, and does nothing in test.

The account's opening balance is **derived from the statement** rather than configured: the raw download
is reverse-ordered, so the oldest transaction is the last row, and working back from its balance keeps
the account consistent with whatever statement is present. `Transaction#sequence` rejects it immediately
if it is wrong.

The three strings that identify a real account — the account name and the two filenames — live in the
encrypted credentials under `seed_data`, because the repository is public. The statement files themselves
are gitignored for the same reason.

---

## The web layer

Conventional Rails: eight controllers, ERB views, no client-side framework.

**Rules are nested under the account.** `ImportMatchersController` lives at
`/accounts/:account_id/import_matchers`, and `account_id` is deliberately absent from its permitted
parameters — the account comes from the route, so a rule cannot be filed against the wrong one. The rule
form sets `url:` explicitly, because `form_with(model: [account, matcher])` would derive
`bank_account_import_matchers_path` from the STI subclass and the route is nested under `:accounts`.

**The counterparty is edited as a name, not an id.** `Transaction#counterparty_name=` resolves a typed name
against `Counterparty`, case-insensitively, and records an unresolved one as a validation error rather than
creating a record — counterparty names are already sprawling and a typo would add to it. A value that already
names the transaction's *current* counterparty is left alone rather than resolved again, because
`#counterparty` is an `Account` and import data can point it at one of the household's own accounts: the cell
then renders a name no `Counterparty` holds, and re-resolving it would refuse a row over a name the user
never typed. `Account#name` is squished on write and case-insensitively unique for the same lookup's sake —
`" Tesco "` would otherwise fail to match itself, and `TESCO` alongside `Tesco` would make the match
arbitrary. The transaction list
therefore renders a text field against a single shared `<datalist>`: a `<select>` per row over several
hundred counterparties would put thousands of `<option>` elements on one page, and the datalist is one list
however many rows are on screen, with no JavaScript. The datalist is rendered once in
`accounts/show.html.erb` and **not** in `transactions/_rows.html.erb`, or every fetched page would append
another element with the same id.

That row's validation error is shown as a red border and a `title` on the input, not as a message beneath it,
because of the row-height assumption recorded below.

**The counterparties list sorts in Ruby, not SQL.** Two of its four columns — the transaction count and the
total — are grouped queries rather than columns on `accounts`, so there is nothing to `ORDER BY`; sorting a
few hundred rows in memory costs nothing and keeps one code path for all four columns. The column is
whitelisted rather than interpolated, since it arrives as a query parameter, and name is the tiebreaker
throughout so that the many counterparties sharing a count still come out in a readable order. It defaults to
name because finding a particular one is the common errand; ordering by total, which is what shows where
renaming pays off, is one click away.

**The categories list sorts in SQL, and shares the heading.** Both its columns are columns on the table,
so there is a real `ORDER BY` to write and no reason to load the table into memory for it. The ordering is
built through Arel rather than as a string — the column arrives as a query parameter, and although the
whitelist already confines it to two values, a hand-spelled `ORDER BY` reads to Brakeman as an injection
and to a reader as one worth checking. `LOWER()` on both sides, or SQLite's binary collation would file
every capitalised name before every lowercase one.

The heading itself — the link, the reversing, the arrow marking which column is in force — is
`ApplicationHelper#sort_link`, shared with the counterparties list rather than written twice. It builds
its link with `url_for` and nothing but the two parameters, so it returns to whichever list rendered it,
and it reads the `@sort` and `@direction` that a sortable list's controller sets. What differs between the
two lists is only how the ordering is *done*, which is where it belongs: in each controller.

**Every Show screen opens with the same strip of actions.** `ApplicationHelper#show_actions` and
`layouts/_show_actions` render Back, Edit and Destroy, in that order, above the record's own data, with
any actions particular to that model in a block between Edit and Destroy. The scaffold's per-screen
`link_to "Edit this account"` lines it replaces sat *under* the record on all five screens, so on a screen
with a list below — an account, a counterparty — the actions were somewhere in the middle of the page; they
were worded differently on each, separated differently, and two of the five drew their destroy button with
no button class at all. A helper wrapping a partial, rather than a partial rendered directly, is what lets
a screen name its four paths and pass its extra buttons as a block — `render layout:` would put the same
thing behind a clumsier call.

Two decisions inside it. **Destroy is pushed to the far end of the strip and always confirms**, because it
is the one action there that cannot be undone and it should not fall under the cursor on the way to Edit;
what the confirmation *says* is each screen's to write, since what is lost differs — an account takes its
transactions with it, a counterparty leaves them behind. And **the strip does not swallow list actions**:
`Add New Transaction` stays above the transaction list, where the row it inserts appears, while
`Manage Import Rules` moved up into the strip because it acts on the account rather than on the list.

This is also why `.pure-button-error` is defined in `application.css`. Pure ships only the primary
variant, so the delete buttons throughout the app — the transaction rows, the rules list, and now Destroy
— had been asking for a class that did not exist and rendering as ordinary grey buttons.

**A Show screen names itself, and its data does not name it again.** Index, new and edit screens all
carried an `<h1>` and a `content_for :title`; three of the five Show screens carried neither, so the strip
of actions was the first thing on the page and the record was identified only by a `Name:` field in the
middle of its own details. Each now leads with a heading — the record's name, or *Import columns for
&lt;account&gt;* where the record has no name of its own — and the `Name:` row has gone from the account,
category and column-layout partials, which is also what removed the column layout's misleading one: it
held the *account's* name under a label suggesting the definition had one. `counterparties/_counterparty`
was nothing but that heading, so it is gone and the heading is in the view, where every other screen keeps
it.

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

**Rendered rows are capped, not merely paged.** Appending each fetched page would leave the document
growing without bound — a reader who scrolled for a while ended up with every row they had passed still
in the DOM. The `transactions_list` Stimulus controller instead keeps every fetched row in a JavaScript
array and renders only a window of `TransactionPage::SIZE` of them, sliding it by half a window at either
edge of the scroll box. Rows leaving the window are **detached rather than discarded**, so scrolling back
re-attaches the same elements: no second request, and any unsaved state in them — a category chosen from
a dropdown — survives, because a detached node keeps its own DOM state.

Sliding the window changes the height above the visible rows, so `scrollTop` is corrected by the same
amount afterwards, or the content jumps under the reader. Rows are one line each, so a single measurement
stands for all of them.

**The box is deliberately shorter than the rows in it.** All of the sliding is driven by scroll events,
and a box tall enough to show its whole window has nothing to scroll, fires none, and strands the reader
on the rows they first landed on. Twenty rows overflow any ordinary screen, so this went unnoticed until
a spec stubbed a smaller window; the controller now caps the box's height against the height of the rows
it holds, while any of them sit outside the window. A list short enough to fit is simply shown.

That leaves the box only just taller than the rows in it, which governs both movements. There is rarely a
step's worth of scrolling to give back, and the two consequences of that were a real defect rather than a
detail:

- *Which way to slide is the reader's direction, not proximity to an edge.* A box within the threshold
  of the bottom is often within the threshold of the top at the same time, and testing the bottom first
  made the list a one-way street — a reader on a tall screen was carried to the oldest transaction and
  could not get back. The controller compares each scroll against the last position and slides only the
  way the reader actually went.
- *A slide never parks the box against an edge that still has rows beyond it.* A box at its own limit
  cannot be scrolled further that way: nothing moves, no event fires, and the window never slides again.
  Correcting `scrollTop` by the height of the rows just detached drove it to exactly that. It is now
  clamped to leave a scroll's worth of room at any end that has more rows — half the available room
  where the geometry is too tight for that.

The controller's own correction is remembered as the last position, so the scroll event it fires reads
as no movement and does not slide the window a second time.

The list therefore scrolls inside a fixed-height box rather than with the page: with only twenty rows in
the document there would be nothing for the page to scroll. That also lets the column headings be sticky.

`transactions#index` answers a bare fragment of rows with the next cursor in a data attribute —
deliberately **not** a Turbo Stream, because a stream would insert the rows into the table on arrival and
the whole point is that the browser decides which of them to render. The end-of-table marker carries the
next page's URL, and an empty one is what stops the scrolling.

One trap worth recording: the query parameter is `as_of`, not `anchor`. Rails reserves `anchor:` in its
URL helpers for the fragment identifier, so `account_path(account, anchor: date)` silently produces
`/accounts/9#2024-06-05` and the value never reaches `params`.

**A row's save button follows that row's state.** Every row is its own form, and a saved transaction
exposes only its category, so a button standing on every row said nothing about which rows had been
edited. The `transaction_row` controller hides it until a field differs from what the server rendered.
What counts as a difference is recomputed from the fields themselves — `defaultValue` and
`defaultSelected` hold the rendered state, and the browser keeps them — rather than being remembered on
the controller instance: windowing detaches and re-attaches rows, which disconnects and reconnects the
controller over an edit that has not been saved, so a flag held on the instance would be lost in exactly
the case that matters. The button keeps its space while hidden, so the delete button beside it does not
move as the reader works down the list.

**The menu bar is sticky, and owns the top of the stack.** It stays at the top of the window while the
page scrolls under it, which is a layout property of every screen rather than anything a page arranges
for itself, so it lives in the layout and one rule in `application.css`. Its `z-index` has to beat the
transaction list's own sticky column headings, which pass underneath it; that is the only stacking
relationship in the application, and it is why either number exists. The `nav` element also used to sit
outside `<body>` — browsers moved it in silently, but a sticky element is better off where it says it is.

**One date format, formatted on the server.** Every date the reader sees goes through the `short_date`
helper and `Date::DATE_FORMATS[:short_date]`, and reads `1-Jan-23`. This reverses an earlier decision: a
`dateinlocale` Stimulus controller used to emit dates as ISO-8601 in data attributes and rewrite them
client-side in the browser's locale. Following the reader's locale sounds better than it read — the
transaction list still printed `01/01/2023` server-side, the accounts index printed an ISO date, and the
date navigation printed a third thing, so one screen showed the same date two ways. For a single-user
application the owner's chosen format beats a locale that is always the same anyway, and the controller
has gone. A date the reader can *edit* is still a native date field, which the browser draws in its own
locale; that is the browser's business, not ours.

**Three Stimulus controllers**, each small:

| Controller | Job |
| --- | --- |
| `csv_analyzer` | Drag-and-drop of detected CSV columns into the definition form |
| `transaction_row` | Offers a row's save button only once the row has an edit to save |
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
`LANGUAGE` environment variable. Displayed dates no longer depend on it, but a date *field* is drawn by
the browser in its own locale, and a spec filling one in types into whatever order that produces — day
first in the UK, month first on a US-defaulted CI runner.

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
corrections, the rules and counterparty screens, the CSV analysis screen, transaction CRUD over Turbo, and
seeding that rebuilds a development database end to end.

The two gaps that matter:

- **Form B has no UI or route.** `FileImporter` is only ever invoked from `AccountSeeder` and from its
  spec. Loading a new statement means dropping into `bin/rails runner`. This is the obvious next piece of
  work, and it is now a much more attractive one, because the categorisation behind it is real: against
  a year's actual downloads, the derived rules categorise about 64% of transactions automatically, and
  85% within the window that was analysed by hand.
- **No analysis or prediction exists yet** — no reporting views, no aggregation by category or period.
  This is the point of the application and none of it is built.

Smaller ones: there is no way to **merge** two counterparties, which is the operation the raw-text names
most want — renaming one and deleting the other leaves its transactions to be re-pointed by hand; a rule
cannot be created from a transaction you are looking at, so its description has to be retyped; and the
accounts index renders raw ISO dates while the show page renders localised ones.

One trap worth recording for whoever writes the next migration: **Rails 8.1's schema dumper sorts columns
alphabetically**, unconditionally. `ImportColumnsDefinition::CSV_HEADERS` used to be derived from
`attribute_names`, which follows the table's physical column order — so the first migration run under 8.1
silently reordered the layout of every CSV the application writes, and broke the CSV analysis system spec.
`CSV_HEADERS` is now spelled out by hand, with a spec asserting it still names exactly the `_column`
attributes the table has.

Until form B gets a UI, the entry points are rake tasks — `import:analysis` to derive the rules,
`import:categorise` to apply the hand labels, and `db:seed` to run the whole chain through
`AccountSeeder`.
