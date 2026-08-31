# Architecture

## What the system is for

`our-accounts` imports statements from UK banks and credit-card providers, categorises the transactions,
and — eventually — analyses and predicts household expenditure. Analysis is the point of the exercise;
importing and categorising are what make it possible.

It is a household application, and the two words are doing different work. Several people sign in, each
with their own password and their own authenticator app; all of them see the same thing, because there is
no notion of an account owner and the database *is* the household's accounts. Authentication without
multi-tenancy: no table carries an owner, no query carries a scope, and the two tables the sign-in added
are the only ones in the schema that are not about money. SQLite on local disk is the store, which is
adequate for a few thousand transactions a year and keeps the whole thing to a directory that can be
copied — and is exactly why the copying is worth thinking about, which the authentication section below
does.

Rails 8.1 on Ruby 4.0.6, Hotwire (Turbo and Stimulus) over importmap, Propshaft, and Pure-CSS installed
through yarn. There is deliberately no JavaScript build step; assets are served as written.

---

## The domain

Six tables carry the whole model.

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

        ManualForecast ──── category

        PaymentSchedule ──── category, counterparty (or a description)
```

`Category` also carries how its spend is predicted — `forecast_method` and an optional
`forecast_months`; `ManualForecast` holds the figures the reader enters by hand for the categories
nothing can be inferred about; and `PaymentSchedule` holds the frequencies they set by hand for
individual payees. Between them they are everything the forecast stores.

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

`Category`'s two sides are deliberately different. `has_many :transactions, dependent: :nullify`, because a
category is only a label: deleting it must keep the spending and merely stop it naming one — and no foreign
key covers `transactions.category_id`, so leaving this implicit left rows pointing at a deleted row.
`has_many :import_matchers, dependent: :restrict_with_error`, because a rule with no category has nothing
left to do, and `import_matchers.category_id` *does* carry a foreign key: without the restriction the delete
raised `ActiveRecord::InvalidForeignKey` out of the controller, which the Show screen's Destroy button made a
one-click 500.

### Merging counterparties, and the two orders that matter

The bank truncates its description field to eighteen characters, and `AnalysisImporter` derives one
counterparty per distinct description, so one payee arrives many times over — `TESCO STORES 2228`, `2555`,
`2889`. Nothing recovers that upstream, so `CounterpartyMerge` repairs it afterwards: a chosen set folds into
one survivor under a name the reader types, which may be a name nothing yet holds.

**What counts as one payee is never inferred.** Sharing a prefix proves nothing in either direction: all five
`LNK ...` entries are one cash-machine counterparty however different their venues look, while `TESCO STORES`
and `TESCO PAY AT PUMP` are the supermarket and the petrol station and must stay apart. Four grouping
heuristics were measured against the real 281 names and only one — stripping digits and punctuation — avoided
false groups; first-word grouping filed twelve unrelated pubs and charities under `THE` and treated `LNK`,
`SQ *` and `PAYPAL` as payees.

**So the shortlist is asked for rather than computed.** `MergeSuggester` sends the names and the categories
their rules assign to the Claude API and gets back proposed sets. What defeated the string heuristics is not
a harder string problem — it is that `LNK` is a cash-machine network and `THE` is an article, which is a fact
about the words rather than about their characters. The measured failures are what the prompt is written
against, and a spec asserts the request carries names and category names only: no amounts, no dates, no
account numbers, nothing per-transaction. This is the one place in the application where anything leaves the
machine.

**It proposes; it never merges.** Every group is a link into the existing confirmation screen carrying the
ids and a suggested name, so `CounterpartyMerge` — where the load-bearing ordering lives — runs unchanged
over a set a person has approved. Three answers are dropped rather than shown, because each would open a
confirmation that cannot work: a name no counterparty holds, a group left with fewer than two members once
those are removed, and a repeat of a set already proposed. A group whose members disagree about their
category is marked rather than withheld — that disagreement is the best available signal a group is wrong,
and it is also how one shop legitimately spans petrol and groceries, so the judgement stays with the reader.

The suggestion is a convenience on a screen that works without it, so every failure — no key configured, the
API unreachable, a refusal, an answer that will not parse — is reported above an otherwise unchanged list
rather than raised. No key configured is the state every checkout starts in, and it has to read as something
to set up rather than as something broken.

**Which provider serves the model is configuration, not code**, and the reason is a constraint rather than a
preference: no API keys are issued here. Development signs in with the Claude Code CLI, production goes
through a third-party service. Both have to work, so the credential is resolved in three steps —
`anthropic.api_key`, then `anthropic.auth_token` with its `base_url` and `model`, then
`CLAUDE_CODE_OAUTH_TOKEN` from the environment. Configured credentials beat the ambient environment: the
first two are deliberate per-environment configuration, the third is whatever the developer happened to
export.

**The OAuth token cannot be passed as a bearer token, which is the trap here.** An OAuth token is only
accepted alongside `anthropic-beta: oauth-2025-04-20`, and the SDK attaches that header on exactly one of
its three auth paths: not `api_key` (which sends `x-api-key`), not `auth_token` (a bare bearer), but the
token-cache path, taken when the credential is an access-token *provider*. So the CLI's token is wrapped in
`Anthropic::Credentials::StaticToken`, whose whole job is to satisfy that protocol with a fixed value.
Handed to `auth_token:` instead it would go out as a bearer with no beta header and come back 401 — a
failure that looks like a bad token rather than a missing header.

The production settings belong in `config/credentials/production.yml.enc` rather than the shared
`credentials.yml.enc`, which is committed and readable everywhere: a gateway token left in the shared file
would have every development machine spending the production budget.

The motive for the gateway is consolidation rather than capability: running the application on a host that
also sells inference puts the model on the same bill. It is worth being clear that this buys nothing
technically — the call works from anywhere, and hosting somewhere does not require the model to come from
there.

Nothing was built for the gateway case beyond those settings. **Structured outputs is undocumented on
DigitalOcean**, and this depends on it; if a gateway rejects `output_config` the portable shape is a single
forced tool call, with `SCHEMA` as the tool's `input_schema` and the groups read from `tool_use.input`, which
that provider does document. That refactor is deliberately deferred: it trades a documented first-party
mechanism for a less direct one, a rejection surfaces through the ordinary error path as a message on the
screen, and one real request settles whether it is needed at all.

**The wanted name is checked against `Counterparty`, not `Account`.** The ids are resolved through
`Counterparty` too, so a `BankAccount` is filtered out of the set by design — and a check over `Account` gave
advice that could not be followed, telling the reader to include an account in a merge that would discard it.
A name held by one of the household's own accounts is still refused, by `Account`'s own case-insensitive
uniqueness validation at the rename, which `#rename_survivor` turns into the error the screen shows.

The differing categories on a group's rules are the best signal available that the group is wrong, which is
why the confirmation lists them per member and warns when they disagree. It only warns: one payee
legitimately spans categories, and merging deliberately changes none — each rule keeps its own description
and `category_id`.

Two orderings inside the merge are load-bearing, and reversing either loses data with nothing to show for it:

- **Re-point before destroying.** `Account#counterparty_transactions` and `#counterparty_matchers` are
  `dependent: :nullify`, so destroying a loser first nulls the very rows being moved.
- **Rename after destroying.** The wanted name is usually held by a member of the set — `Spotify` is held by
  `SPOTIFY`, which is being folded in — and `Account` validates `name` uniqueness case-insensitively across
  the whole STI table, so renaming first fails against a record about to disappear.
- **Move the hand-set payment frequencies before destroying**, which is the first instruction again by the
  opposite mechanism: those rows would have been *nullified*, these would have been *destroyed*, since
  `Account#counterparty_payment_schedules` is `dependent: :destroy`. This is also the moment a frequency is
  most wanted — a series split across two counterparties is not recognised at all, merging is the repair,
  and losing the cadence on the way would undo half of it. It cannot go through the same `update_all` as
  the other two: `payment_schedules` is uniquely indexed on `(category_id, counterparty_id)`, so a blanket
  re-point collides wherever the survivor is already ruled on in that category. There the survivor's own
  ruling wins — it is the one set against the name being kept — and the loser's is dropped, because two
  cadences for one payee cannot both be right and nothing here can tell which. The notice says how many
  moved, so a ruling that went does not go silently.

All three are pinned by specs verified to fail when the order is inverted rather than merely to pass as written.
Checking that caught a fault in the second: it originally made `SPOTIFY` the survivor, and a record is
excluded from its own uniqueness check, so it passed whichever order was used. The survivor is the lowest id
in the set, matching `Account.scope :named`, so the record other code already resolves to is the one kept.

Ids resolve through `Counterparty`, never `Account`: `Transaction#counterparty` is declared
`class_name: "Account"` and nothing in the schema forbids one of the household's own accounts being named as
a counterparty, so without that scope a hand-edited form could fold away the account holding every
transaction.

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
rather than producing thousands of subtly wrong records. The message names the row, both balances and the
two things usually behind the difference, because it is now read on a screen by whoever chose the file
rather than in a terminal by whoever wrote the importer.

**Everything above assumes the preceding transaction is one `sequence` itself placed.** A transaction added
by hand through the UI is not: `TransactionsController` permits neither `balance` nor `day_index` and never
calls `sequence`, so it carries null in both. That was unreachable while a statement was only ever loaded
into an empty account, and the import screen makes it ordinary. The missing `day_index` is coalesced to
zero, as `Transaction::ORDER` already does for the same null. The missing balance is **refused by name**,
which is the more important of the two: `previous&.balance || opening_balance` reads as a sensible default,
but where the predecessor is real and merely has no balance of its own it restarts the running total as
though the account were empty — producing a figure wrong by everything in between, and on a statement
carrying no balance of its own, wrong with nothing to catch it.

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
amount, the balance, and so on. `FileImporter` parses the file in full, then walks it calling
`Transaction#find_match` → `Transaction#sequence` → `save!` for each row that is not already loaded, and
returns itself carrying counts of what it did.

**Parsing happens before anything is written**, which is the difference between a refusal and a rollback.
Everything the factory can object to — a date the format cannot read, a statement downloaded for the other
account — is settled while the account is still untouched, and each objection can name the line of the file
it came from. A few thousand unsaved records cost nothing. The mapped column names are checked against the
file's own headers in the same pass, and that check has to be explicit rather than caught as it goes wrong:
the factory reads each mapped column straight off the row, so a name the file does not carry arrives as
`nil`, and `nil.to_f` is `0.0`. A mis-mapped balance column therefore used to report every balance as
£0.00 and tell the reader their account did not reconcile — true, but a description of the symptom that
sent them to the wrong screen.

**The whole file is one database transaction.** Every row used to be its own `save!`, so a statement that
stopped part-way left the rows before the failure behind and nothing to say where it got to — the outcome
the README warned readers about rather than one the application prevented. All or nothing is what lets the
import screen open every failure message by saying nothing was imported. `#sequence` reads back rows
written earlier in the same loop, which is safe because they are the same connection's own uncommitted
writes; and under transactional fixtures the inner transaction is a real savepoint, because Rails opens the
fixture transaction `joinable: false` — so the guarantee is directly testable, and a spec asserts the table
is empty after a refusal.

**Rows already loaded are skipped rather than duplicated.** Statements are downloaded by date range and
those ranges overlap: the natural way to catch up is to download the last couple of months and load the
lot. That used to double the rows up until `#sequence` refused one on a balance it could no longer
reconcile, which is why `AccountSeeder` guarded it by declining to import into an account holding anything
at all — the cruder of the two behaviours, since it also refused a statement that had merely grown.

What counts as the same row is `[date, description, amount_pence]`, and the balance too where the layout
has a balance column. It is a **tally rather than a set**, and the difference is not pedantic: a statement
legitimately repeats the same description and amount on the same day — two coffees from one shop — so a
set would silently drop the second for ever. Counting each existing row once and consuming one per match
means a file holding two identical rows against a database holding one loads exactly one of them. The
counts are `pluck`ed rather than loaded, since the range can span a year and every row of it only becomes
a hash key.

**The rules are loaded once, not once per row.** `ImportMatcher.find_match` takes an optional preloaded
collection, and `FileImporter` passes one. Without it, every row queried and instantiated every rule the
account has — against the real statement, 2,626 rows over 282 rules, measured at 9.1 seconds against 5.1
with the rules held. Passing an array cannot leak a rule across accounts, because `#match` re-checks
`account_id` itself; it does have to be `in_match_order`, since that is what makes a literal beat a regex.

That, with an index on `transactions (account_id, date)` for `#sequence`'s per-row lookup, is what makes
an import runnable inside a web request. A real 2,626-row statement takes about five seconds; a month's
download is a few hundred rows, and re-loading a file already imported is a tenth of a second, because
nothing is written.

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
- **A layout with no balance column has no integrity check at all**, which is the cost of the paragraph
  above and worth stating plainly. Where the statement carries a balance, `#sequence` compares the two and
  a missing period is caught on the first row. Where it does not — Barclaycard — the balance is derived and
  never verified, so statements loaded out of order, or with a month missing between them, produce a
  running balance wrong by a constant with nothing anywhere to say so. Skipping duplicates still works, as
  that only needs the date, description and amount; detecting a *gap* is what cannot be done. Refusing a
  file that does not abut what is loaded was considered and rejected: card statements arrive month by month
  and legitimately abut without overlapping, so the rule would refuse the ordinary case.
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

A second thing it lost, until recently, was time. `ImportMatcher.find_match` is called from one place in
the pipeline — `FileImporter`, as each row is read — so a rule written by hand only ever affected the *next*
import. That is the wrong way round: a rule gets written *because* something already imported went
uncategorised, and the row that prompted it would have stayed blank. `RuleApplication` closes that
direction. `ImportMatchersController` runs it after a rule is saved, on create and on update, and the flash
reports the count.

Four decisions in it are load-bearing:

- **It claims only rows where `import_matcher_id` and `category_id` are both null.** Those two nulls are the
  whole of "hand judgement wins", the same principle `AnalysisCategoriser` embodies: a null category means
  nobody chose, and a null matcher means no rule got there first on match order. Overriding either would
  silently reverse a decision somebody made deliberately. The visible consequence is that a rule's
  **Matched** count can read one lower than the number of transactions sharing its description — the row
  categorised by hand before the rule was written keeps its category and stays unclaimed.
- **`ImportMatcher#match` is the single authority.** It is duck-typed on `account_id`, `trx_type` and
  `description`, which a saved `Transaction` satisfies exactly, so it is reused unchanged rather than
  reimplemented in SQL. The literal case *is* narrowed by a `where(description: …)` first, which is a pure
  narrowing because the column collates `BINARY` — the same comparison Ruby's `==` makes — but `#match` is
  still asked, so the two paths cannot come to disagree about what a rule means. A pattern has to be
  compared in Ruby regardless: SQLite has no `REGEXP`.
- **`update_all`, for the reason `CounterpartyMerge#repoint` gives.** No callback on `Transaction` needs to
  run to re-point three foreign keys, and `#sequence` must emphatically *not* run — the balances are already
  correct, and re-deriving one against itself would raise `ImportError`. `updated_at` is left alone: a rule
  claiming a row is not an edit the reader made to that transaction.
- **A rule naming no counterparty leaves the row's own alone.** `Transaction#find_match` assigns the rule's
  counterparty unconditionally, which is safe at import time because the row has none to lose. Applied
  backwards it is not — the counterparty may have been created from that very row a moment earlier.

It is invoked from the controller rather than from a callback on `ImportMatcher` because `AnalysisImporter`
creates a few hundred rules in one run, against an account whose statements are already imported; a callback
would turn one rake task into a few hundred silent sweeps of the transactions table and quietly change what
re-seeding means.

`AnalysisCategoriser` puts those judgements back, after the import, by matching analysis rows to
transactions on **date and running balance**. That pair is unique — a running balance cannot repeat
within a day — and it is reliable by construction, because `Transaction#sequence` has already verified
each imported balance against the same statement. Description and amount would not do: descriptions
repeat with the same amount on the same day.

### Seeding ties it together

`AccountSeeder` runs the whole chain in order — account, columns definition, rules, import, labels — and
is what `db/seeds.rb` calls. Each step is idempotent or skipped once done, so seeding can be re-run
against an existing database. The import step is idempotent because `FileImporter` is: this class used to
guard it by refusing to import into an account holding any transactions at all, which was the right
instinct and the wrong place — it also declined a statement that had merely grown since the last seed.
Recognising a row belongs in the loop that can see one row at a time. `AnalysisImporter` therefore **skips a description this account already has a
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

## Forecasting

Predicting what a calendar month will cost is what the importing and categorising were always for. The
whole of it lives under `app/models/forecast/`, and is arithmetic over the transactions rather than
anything held on disk.

### Nothing is stored but the configuration

There is no forecast table. Each request rebuilds the month from the transactions; the only things
written down are the method chosen on each category, the figures typed in by hand, and the frequencies
set by hand for individual payees.

The alternative was a snapshot — a row per category per month, written when the forecast was generated —
which would have bought a record of what was predicted against what happened. It loses because a stored
forecast goes stale the moment the next statement is imported, and a number on screen that disagrees
with the transactions underneath it is worse than no number at all. It would also need a regeneration
step, which is a thing to remember to do. Recomputing costs milliseconds over a few thousand rows, and
a month that has finished already shows how the forecast did by comparing what was spent against what
the same arithmetic predicts.

All three stored things pass that test, which is what makes them configuration rather than cache. A
frequency set by hand is an assertion by the reader about how a payee behaves, exactly like the method on
the category; every number derived from it — the amount, whether it is due, whether the payee has gone
quiet — is still computed from the transactions on every request, so there is nothing in it that the next
import can contradict.

What is new with the frequencies is that configuration can now outlive its subject. A ruling names a
payee, and a payee can go: recategorise its transactions, or merge its counterparty away, and the row
remains with nothing to apply to. That is why `Forecast::RegularPayments` builds its candidates from the
union of the payees in the history and the payees it holds rulings for, rather than from the history
alone — otherwise the row would appear on no screen at all, and the only place able to withdraw it could
not show it. It is listed, saying it is doing nothing, which is the same instinct as everything else in
this section: the store may hold something useless, but not something invisible.

### A category says how it is predicted

`Category#forecast_method` is one of four, because categories differ in kind rather than in degree:

- **`monthly_average`** — the mean of recent complete months. For Food and Car, which are steady in
  aggregate and unpredictable one transaction at a time.
- **`regular_payments`** — the individual direct debits and subscriptions, recognised from history and
  predicted one at a time. For Utilities and Subscriptions.
- **`manual`** — the reader's own figure. For Holidays, where the spending is real and large and the
  history says nothing whatever about next month.
- **`excluded`** — left out. For paying off a card and moving money between the household's own
  accounts, which is not spending: the spending already happened on the card, and counting it here
  would count the same money twice.

The setting lives on `Category` rather than in a table of its own. A one-to-one settings table would
have needed a row conjured for every category before it could be configured, and a null-object dance
for the ones without one. Excluding transfers through a fourth enum value, rather than an `internal`
boolean or a way of excluding whole accounts, keeps it to the concept already there.

The enum is declared `prefix: :forecast, scopes: false`. The prefix keeps the predicates meaningful —
`category.forecast_manual?` rather than a bare `manual?` on a Category. Suppressing the scopes matters
more than it looks: the obvious name for the first value is `average`, and the generated
`Category.average` would have sat on top of `ActiveRecord::Calculations#average`. Nothing needs a scope,
so none is generated and the collision cannot recur under a different name.

### Spend is positive here, and negative everywhere else

Inside the module every figure is a positive magnitude. The conversion happens in one place,
`Forecast::History`, and nothing else in the module touches `amount_pence`.

Three things force it. The central rule is `[expected - actual, 0].max`, whose negative twin reads as a
bug at every review forever. The reader types `600` for a holiday, not `-600`, so a hand-entered figure
has to be stored positive — and a stored positive cannot sit beside computed negatives in one column.
And the screen shows outgoings only, so the sign distinguishes nothing and would only paint every row in
the red that elsewhere means "money left an account".

Staying negative throughout was the alternative, and its merit is real: one convention across the whole
application, and a forecast figure directly comparable with a transaction amount. It loses to the clamp
and the typed-in figure.

### Everything counts in whole months

A month is an index — `year * 12 + month` — and a gap between payments is a subtraction. That is what
makes February, leap years and thirty-day months a non-question rather than a list of cases to handle;
the only day arithmetic in the module is the one range that picks out a month's own transactions. There
is deliberately no pro-rating by days elapsed: the rule is a whole month's prediction less what has
already gone, and a daily burn rate is a different question nobody asked.

### Remaining belongs to the strategy, not the line

This is the design's one real idea, and it comes straight out of the requirement.

`Forecast::Line#actual` is the same thing under every method: everything spent in the category this
month, including spending no method predicted. `remaining` is not, because how much is still to come
depends entirely on how the prediction was arrived at.

Suppose Utilities expects the energy bill at £218 and the water bill at £40. The energy bill goes out at
£248. Subtracting at the level of the category gives `£258 − £248 = £10` — which has quietly eaten £30
of a water bill that has not been paid and is still going to be. Settling the payments one at a time
gives £40, and goes on giving £40 whatever the energy bill came in at, because that payment is done. The
projected total then reads £288 against an expectation of £258, which is the honest answer rather than
an error.

So the line owns `actual` and `projected`; the strategy owns `expected` and `remaining`. Strategies take
a **set of rows** rather than a `Category`, which is what lets the uncategorised line below be the same
code with a different scope instead of a special case threaded through four classes.

### The average, and what it divides by

The window is the N complete months before the month being forecast — not before today, so that a
forecast for March reads the same in June as it did in March, and a month gone by is a fair test of the
method. The window end is *also* held to the last month that has actually happened, or a forecast three
months out would average over months that do not exist yet, each contributing nothing and dragging the
prediction down by a third.

The divisor is the number of those months the **records** cover, not the months the **category** has
existed for. Dividing by the category's own history would make one £600 transaction four months ago
predict £600 every month forever. Dividing by the records' coverage means a month in which the household
genuinely spent nothing on Food did happen and does pull the average down — which is what an average of
recent months is supposed to mean.

The cost is a category younger than the window, averaged over months of zeroes and reading low.
`Category#forecast_months` is the remedy, and the workings page prints the months with the zeroes
visible so that the cause is discoverable — a knob nobody can see the need for is not a remedy.

### Recognising a regular payment

Detection runs over **all** history rather than the average's window. A six-month window holds at most
one occurrence of an annual insurance premium, so it could never reach the two occurrences a cadence
needs; two years of history finds it at once, and the categories using this method are few enough that
loading all of them is a few hundred rows.

What replaces the window is a **staleness rule** expressed in the payment's own cadence: a payment is
live only if its last occurrence is at most `cadence + 1` months back. That is strictly better than a
fixed window — a monthly payment gets two months of silence, a quarterly one four, an annual one
thirteen — and without it a subscription cancelled three years ago has a spotless monthly cadence and
reads as due every month for ever.

The rest: a payee is its counterparty where it has one and its exact description where it has not, since
plenty of direct debits never acquired one. The cadence is the median gap in months, snapped to the
nearest of 1, 3, 6 and 12, because a raw median of two or five is noise around one of those rather than
a schedule anything is on. The predicted amount is the **most recent** occurrence rather than an average
of them — the whole reason to use this method instead of the average is that a direct debit steps up and
the new figure is what next month costs, and averaging lags precisely the change the method exists to
catch. The price is a genuinely variable bill, where the answer is to forecast that category by its
average instead.

**Every payee produces a candidate, not only the ones that pass.** There are five ways a payee ends up
outside the forecast — one occurrence in a completed month, none at all, a median gap above twelve
months, silence longer than the staleness rule allows, and a ruling by the reader — and each of them is
named with its reason, on the workings page and on the category's own screen. Only the erratic ones used
to be reported, which meant the most consequential case, a new direct debit invisible until its second
occurrence, was the one that vanished without trace. Silence here is money missing from the total with
nothing to explain it, which is worse than a poor prediction.

### Correcting the detector

Two of those five rejections are *inferences*, and the reader knows things the history does not. So a
`PaymentSchedule` — one row per payee per category, existing only where the reader has ruled — can name
a payee's frequency outright, or say it is not a regular payment at all.

**A frequency given by hand overrides the two-occurrence minimum and the erratic test.** Both exist only
because one sighting, or a ragged set of them, cannot *measure* a cadence — and being told one settles
the question those tests were asking. This is the main thing the feature is for: a direct debit paid once
is otherwise invisible for a month.

**It does not override the staleness rule.** That rule is not an inference about how often a payment
comes; it is a statement that *this payee has stopped*, which naming its frequency cannot have been meant
to deny. Without it, a cancelled direct debit named by hand would be forecast for ever — the exact
failure the staleness rule was invented for. It is measured against the frequency the reader gave, so
their answer still shapes it.

**One occurrence is still needed**, whatever the reader says, because the amount is the most recent
occurrence and there is nothing else it could be. A payee whose only payment falls inside the month being
forecast therefore joins the forecast the month after; it has already gone out, so nothing is owed for it
either way.

Three details of the record are load-bearing:

- **Its identity mirrors the detector's grouping key**, `counterparty_id || description`, and the two
  agreeing is not tidiness. If they diverged the ruling would simply never be found, and the screen would
  save a frequency that did nothing.
- **Three states live in one nullable column.** No row means "work it out"; a row with a cadence means
  that cadence; a row with none means "not a regular payment". Zero as a sentinel lost because it would
  reach the `silence % cadence` arithmetic and raise; a separate boolean lost because it spends two
  columns and a cross-column validation on three states.
- **Two partial unique indexes, not one over three columns.** SQLite treats NULLs as distinct, so a
  single index on `(category_id, counterparty_id, description)` would happily hold the same counterparty
  twice, both rows having a null description.

The counterparty side is `dependent: :destroy`, where a counterparty's transactions and rules are
`:nullify`. That is not an inconsistency: a nullified `counterparty_id` with no description would leave a
row naming nobody, and there is nothing to preserve, because the transactions released by the delete
regroup under their own descriptions.

### The uncategorised line

`transactions.category_id` is nullable and about a third of real transactions have none. Left out, the
headline total would be a third short with nothing on the page to say so, so everything uncategorised
gets a line of its own, predicted by average because unclassified spending has no structure to exploit.
Sitting high, it is also the standing argument for writing another import rule.

Refunds — positive amounts inside a spend category — are ignored, because `Transaction.spend` filters to
negatives. Averages therefore read very slightly high. Netting each category would be more honest for
the real categories and nonsense for this one, because salary lands here: netting would make
Uncategorised positive and the line would invert or disappear. One rule for everything beats two.

### Two queries, not a hundred and eighty

`Forecast::History` loads the window across every category at once, and all history for the few
categories forecast from their payments. Building the page a category at a time would be a query per
category per month.

The two small configuration loads follow the same rule: `Forecast::Month` reads the month's hand-entered
figures and every hand-set payment frequency once for the page, not once per line.

Rows are `pluck`ed and grouped in Ruby rather than grouped by `strftime('%Y-%m', date)` in SQL. That
keeps SQLite's date functions out of the application and follows `CounterpartiesController#index`, which
sorts its derived totals in memory for the same reason. The escape hatch, if a few thousand rows ever
stops being milliseconds, is to push the grouping into the query.

`app/models/forecast/` is the first subdirectory under `app/models`, which the flat neighbours
(`AnalysisImporter`, `FileImporter`, `TransactionPage`) do not need. Eight small classes that only make
sense together earn it, and two of them — `Month` and `Line` — have names far too generic to sit at the
top level.

---

## The web layer

Conventional Rails: thirteen controllers, ERB views, no client-side framework.

**Rules are nested under the account.** `ImportMatchersController` lives at
`/accounts/:account_id/import_matchers`, and `account_id` is deliberately absent from its permitted
parameters — the account comes from the route, so a rule cannot be filed against the wrong one. The rule
form sets `url:` explicitly, because `form_with(model: [account, matcher])` would derive
`bank_account_import_matchers_path` from the STI subclass and the route is nested under `:accounts`.

**Loading a statement is nested under the account too, and for a stronger reason.** `StatementImportsController`
lives at `/accounts/:account_id/statement_imports`, with `new` and `create` only. The account is not merely
the owner of the result: it is what says how the file is laid out and what the running balance continues
from, so it has to come from the route rather than from a field on a form that could name the wrong one.
The operation is the noun, as with `CsvAnalysesController` and `CounterpartyMergesController`, and there is
no record to show afterwards — what an import produces is the account's own transaction list, which is
where `create` lands.

**One step, not a preview and a confirmation.** The obvious shape, following `counterparty_merges`, would
have been a `new` that showed what was about to happen and a `create` that did it. It was rejected because
the file would have to be kept alive between the two requests — ActiveStorage's engine is configured but has
no tables and is used nowhere, so that means a path in `tmp/` and something to sweep it — in exchange for a
reassurance that atomicity already provides. Since the whole file is one database transaction, every failure
message can open by saying nothing was imported and be telling the truth, which is the thing a preview would
have been for.

**The button does not disappear when the account cannot use it.** An account with no `ImportColumnsDefinition`
still shows **Import Statement**, and the screen behind it explains why nothing can be read and links to the
form that fixes it. Hiding the button would leave a reader with nothing to click and no account of why, and
the strip should read the same on every account, which is the point of `show_actions`. A flash could say as
much but could not carry the link.

It rescues `ImportError` alone, deliberately unlike `CsvAnalysesController`'s blanket `rescue => e`. That
controller renders into a Turbo frame, where an unhandled exception leaves the frame blank with nothing
said; this one redirects, so Rails' own error report is a better account of a genuine bug — and the
transaction has already rolled back, so nothing is at stake in letting one through.

**The counterparty is edited as a name, not an id.** `Transaction#counterparty_name=` resolves a typed name
against `Counterparty`, case-insensitively. A value that already names the transaction's *current*
counterparty is left alone rather than resolved again, because `#counterparty` is an `Account` and import
data can point it at one of the household's own accounts: the cell then renders a name no `Counterparty`
holds, and re-resolving it would refuse a row over a name the user never typed. `Account#name` is squished
on write and case-insensitively unique for the same lookup's sake — `" Tesco "` would otherwise fail to
match itself, and `TESCO` alongside `Tesco` would make the match arbitrary. The transaction list therefore
renders a text field against a single shared `<datalist>`: a `<select>` per row over several hundred
counterparties would put thousands of `<option>` elements on one page, and the datalist is one list however
many rows are on screen, with no JavaScript. The datalist is rendered once in `accounts/show.html.erb` and
**not** in `transactions/_rows.html.erb`, or every fetched page would append another element with the same
id; a save that creates a counterparty appends the one extra `<option>` as a second Turbo Stream, so the
rest of the rows offer it without a reload.

**A name no counterparty has is confirmed, not refused.** It used to be a flat validation error: creating a
record on a typo would add to the sprawl of raw statement names `AnalysisImporter` already left behind, so
the reader was sent to the Counterparties screen instead. That argument still holds, but the detour was paid
on every genuinely new supplier, which is exactly when the need arises. So the guard moved rather than went:
the first save comes back marked, and saving the row a second time creates the `Counterparty`.

Three things shape how that is carried:

- **The confirmation is the name, not a flag.** The row round-trips it through a hidden
  `confirmed_counterparty_name`, and `Transaction#accept_confirmed_counterparty` only acts when it still
  matches what was typed. A bare "yes" would survive an edit to the field and create the name the reader had
  just corrected away from.
- **The new record is written by `belongs_to` autosave**, inside the transaction's own save and so in one
  database transaction. Autosave does not check whether that write succeeded when `:autosave` is unset, so
  anything the record would reject has to be caught on the `Transaction` first — otherwise the row would
  save with a silently empty `counterparty_id`. That is why a name too short to be one, or belonging to one
  of the household's own accounts, is refused outright with its own message rather than offered: saving
  again could only fail again. Declaring `autosave: true` instead would file Rails' errors under
  `:counterparty`, where the row is not looking.
- **The save button has to survive the rejection.** `transaction_row_controller` decides a row is edited by
  comparing each field with its `defaultValue`, and the server has just rendered the typed name back as that
  default; hidden inputs are filtered out of the comparison. Without a `pending` value forcing the button
  visible there would be nothing left to press. Its `title` names what the next press will create.

**The words go outside the row, because inside it there is only room for a colour.** A message beneath the
field is unavailable — the row-height assumption recorded below — so the first version of this said
everything through a red border and two `title` tooltips. That reads as a save that failed and will not say
why: a reader who does not think to hover sees a red field, no text, and their category edit apparently
thrown away. It was reported as a bug within a day of being built.

Two changes, neither of which touches the row's height:

- **A question is no longer coloured like a failure.** `field-pending` is amber where the row is offering to
  create a name; `field-error` stays red where the name cannot be saved at all. They shared one class before,
  so an invitation to confirm and a flat refusal were indistinguishable — and the only visible difference,
  whether the save button survived, is not something a reader reads as the distinction.
- **The message itself is a second Turbo Stream** into `#transaction-message`, an empty div above the list.
  It is replaced on *every* create and update rather than only the rejected ones, because replacing it with
  an empty container is what clears a question the reader has since answered; streaming only on failure
  would leave the last one on screen for ever. `layouts/_notice` could not be reused: it draws its
  containers only when a flash is set, so there would be nothing in the document to target on the first
  rejection. Both messages say that the rest of the row is *held* rather than lost, which is the part a
  coloured border cannot express and the part the reader actually doubts.

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

**A category reads its counterparties from both sides.** The relationship exists twice — `transactions`
carries `category_id` and `counterparty_id`, and so does `import_matcher` — and the two answer different
questions, so the category Show screen shows both rather than picking one. The spend rollup says who was
actually paid and what it came to; the rules say which counterparties are wired to file here, which is
visible before a single transaction has landed and is what a category with no history has to show. The
rules table also puts the records that `:restrict_with_error` would refuse a delete over on screen
*beforehand*, where previously they were only named in a flash after the Destroy button had already failed.

`Category#counterparty_spend` does the rollup as one grouped `pluck` plus one load, and orders in Ruby for
the reason `CounterpartiesController#index` does: the count and the total are grouped values, not columns to
`ORDER BY`. It lives on the model rather than in the controller, which is where the counterparties list does
the same arithmetic — that one aggregates over every counterparty at once and so has no single record to
hang off, whereas this one is a question about one category and is worth unit-testing as such. The order is
fixed at largest-spend-first rather than made sortable like the two index screens: a list inside a Show
screen is there to be read, not navigated, and the one ordering worth having is the one that names the
biggest payees. Amounts being negative, that ordering is `sort_by` ascending — the same trap as in
`sort_key`, and the reason both carry the comment.

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
`Manage Import Rules` and `Import Statement` moved up into the strip because they act on the account rather
than on the list. Importing is drawn first of the two, being the errand that brings you to an account most
months, where the rules are looked at occasionally.

This is also why `.pure-button-error` is defined in `application.css`. Pure ships only the primary
variant, so the delete buttons throughout the app — the transaction rows, the rules list, and now Destroy
— had been asking for a class that did not exist and rendering as ordinary grey buttons.

**A class that silently does nothing is the recurring trap with Pure, and forms have their own version of
it.** `pure-control-group` and `pure-controls` are defined *only* under `pure-form-aligned`, so a form
carrying the two class names without the modifier gets no spacing at all and its label, field and buttons
abut. Both upload forms had exactly that. Which modifier to reach for depends on the room available: the
statement import screen is full width and now matches every other form at `pure-form-aligned`, while the
CSV analyser panel is a third of the width, where an aligned form's ten-em label and eleven-em button
indent have nowhere to go — so it is `pure-form-stacked`. Pure spaces a stacked form's *fields* but not
the buttons under them, which is the one line of `.pure-form-stacked .pure-controls` in `application.css`.

The forecast's own pages deliberately do **not** use the strip. `show_actions` requires an edit path and
a destroy path, and a forecast page is a report about a month rather than a record: there is nothing to
edit as a record and nothing to delete. They open with a plain Back link instead, in the same position.

**Every screen that is not a top-level destination opens with a strip of navigation, and the form screens
have their own.** `ApplicationHelper#form_actions` and `layouts/_form_actions` draw Back to the list and,
where there is a record already, Show to look at it as it stands — under the heading, above the form. The
Show strip above was only half the job: New and Edit screens were left as the scaffold wrote them, with a
plain text link in a bare `<div>` after a `<br>` at the foot of the page, worded differently on each
(*Back to accounts*, *Back to rules*, *Back to import columns definitions*). The category edit screen is
what exposed it. Since a category predicted by its regular payments carries the table of them below the
form, its two links sat under a table and two paragraphs of explanation — off the bottom of the screen, so
in practice that screen had no way back at all. `import_matchers/edit` was worse in a quieter way: it
offered Back but no way to reach the rule being edited, so that link is new rather than moved.

Three decisions inside it. **There is no Destroy on a form screen** — a form offers nothing to delete that
its own Show screen does not, and the one irreversible button in the application should not sit within
reach of Save. **The labels are the bare words Back and Show**, for the same reason the Show strip uses
three fixed words: a reader learns the position once, and a spec can `click_link 'Back'` on any screen
rather than knowing which model it is looking at. And **`.form-actions` is a second selector on the
`.show-actions` rule** rather than a copy of it; the two strips hold different things but are laid out
identically, and `.show-actions` could not simply be reused for both because `spec/system/show_actions_spec.rb`
selects on it to assert what a *Show* screen contains.

The merge confirmation screen takes the strip as well, and keeps its own `Cancel` beside `Merge`. The two
are not the same thing: `Cancel` is that screen's answer to the question it asks, and belongs with the
button that says yes, while `Back` is where the way out lives on every other screen — reachable without
reading the whole page first, which on a merge of a dozen names is the point.

The rule reaches one list, too. `import_matchers/index` is the only index in the application reached from
somewhere other than the sticky menu bar — the other four *are* menu-bar destinations, so "back" from them
would mean nothing — and it had the same plain text link, below its explanatory paragraph. It now draws
`form_actions` with a back path and no show path. `New rule` stays at the foot of the list, following the
same rule as `Add New Transaction`: the strip does not swallow list actions.

Transaction rows are the deliberate exception, because the row *is* the form. That is now true rather than
nearly true: `transactions/new.html.erb` and `transactions/edit.html.erb` have been deleted and `:edit`
dropped from the nested route. Neither template could work. `TransactionsController#new` renders its Turbo
Stream inline, so the first was unreachable — and would have failed if reached, naming a `transactions_path`
that is not a route and a `transactions/_form` partial that does not exist. The second had no controller
action at all, which under Rails' implicit rendering meant the route *did* reach it, rendering
`_transaction_as_row` without the `account:` and `categories:` locals it requires. Nothing linked to
either, and nothing referenced `edit_account_transaction_path`.

**The forecast is one screen and a workings page behind each line.** `ForecastsController` is read-only
and takes the month as `?month=`, coercing anything unreadable — or absent — back to
`Forecast::Month.default_month` rather than raising — the same view `TransactionPage#coerce_date` takes of
a date arriving as a parameter — and clamping it to the same bounds the navigation buttons show, so a
hand-edited URL cannot strand the reader where the buttons would not go.

**It opens on the last month with a transaction in it, not the calendar's current month.** Statements are
downloaded and imported in arrears, so for most of a month the current one holds nothing or a few days of
it, and landing there showed a full set of predictions with almost no actuals against them — the reader's
first move was always to press **«**. `default_month` is `Transaction.maximum(:date)` rounded to its
month, falling back to this month on an empty database, and sits beside `earliest_month` and
`latest_month` as a class method because the controller needs it before it has a forecast to ask. The
consequence is that the default view is usually a *past* month, so the screen's "jump to this month" link
has to name today's month explicitly rather than linking to the bare `forecast_path` it once did. Month navigation reuses the disabled-span pattern of
`TransactionsHelper#transaction_anchor_link`, for the same reason: the controls keep their positions.

A **workings page per line** rather than rows that expand. There is no JavaScript build step, the
existing Stimulus controllers each earn their keep, and a fourth written for disclosure would not — while
a page has room to print the months an average is taken over, or every recognised payment with the date
and amount of each occurrence that has already gone out. That page is where the reader can check the guess,
which is the difference between a forecast they can act on and a number they have to take on trust.

**What has gone out is a list, not a date and a total.** A payment on a monthly cadence can still fall twice
inside one calendar month — billed on the 1st and again on the 29th — and the first version reduced the
occurrences two different ways: it totalled the amounts but kept only the earliest date. Two ordinary £7.99
charges were drawn as a single charge for £15.98, which on the one page whose purpose is checking the guess
reads as a bill that has doubled. `Forecast::Payment#landed` carries the occurrences themselves and the cell
prints a line each; no total is kept, because nothing needs one. The alternative was a count beside the
total — "2 payments, £15.98" — which is honest but still withholds the dates the reader needs in order to
recognise them. None of the arithmetic was ever wrong: `remaining` asks only whether a payment has landed,
so it never read the total.

The hand-entered figure is **an upsert on one route**, `POST /forecast/categories/:id/manual`, reached
from the workings page: `find_or_initialize_by(category, month)`, saved, or destroyed when the field is
left empty. A full `resources :manual_forecasts` would be five routes and two more screens around a
record that is a single number. Emptying the field deletes rather than storing zero, because "I have not
said" and "nothing will be spent" are different statements and the screen shows them differently — a
category awaiting a figure reads **not set**, and the count of them is reported above the table, that
being much the likeliest way for the headline total to be quietly too small.

The hand-set frequencies are **a second upsert**, `PATCH /categories/:category_id/payment_schedules`, and
they take a whole screenful in one submission rather than a form per row. With no JavaScript there is
nothing to save a row in place, and the reader rules on several payees at a sitting, so one **Save
frequencies** button is both simpler and closer to how the screen is used. A row arrives as a hash inside
an array — `payment_schedules[][counterparty_id]`, `[][description]`, `[][cadence_months]` — read with
`params.expect(payment_schedules: [ [ ... ] ])`, whose doubled brackets are what make it refuse a hash
arriving where the array belongs. The shape carries one constraint worth knowing: Rack starts a new hash
in a `name[]` array only when it meets a key the last one already has, so every row must render all three
fields, in the same order, and none of them may be a checkbox — a row that skipped a field would merge
into its neighbour and both rulings would land on the wrong payee.

Configuration has no screen of its own: the method and the lookback are two more fields on the category
form, and the method is a sortable column on the categories list — ordering by it answers "which are
still on the default?". The payees of a regular-payments category are a table on the same form, below it,
in `categories/edit` rather than the shared `_form` — the partial is shared with `new`, where there is no
history to list, and one `<form>` cannot be nested inside another. With no JavaScript the table cannot
appear as the method select changes, so it appears when the *saved* method is regular payments, and the
select carries a note saying so. That is the same compromise the lookback field already makes, and it
costs one extra click after switching a category over.

That table asks about `Forecast::Month.default_month`, not today's month, for the same reason the forecast
opens there: against statements imported in arrears the calendar's current month holds nothing, and asked
about it every payee in the category reads as having gone quiet. It also keeps the two screens answering
about the same month, which is the only thing that makes them comparable — the table is meant to explain
the figure on the workings page, and it cannot do that from a different month.

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

**Dates are formatted on the server, through a helper, in one of two registered formats.** Every date
the reader sees goes through the `short_date` helper and `Date::DATE_FORMATS[:short_date]`, and reads
`1-Jan-23`. The forecast adds the second: it is about a whole month rather than any day in one, and
`1-Mar-26` would claim a precision it does not have, so `month_name` and
`Date::DATE_FORMATS[:month_year]` give `March 2026`. The rule being kept was never "exactly one format"
— it is that no view spells out a `strftime` of its own, so that changing how a date reads is a change
in one place. This reverses an earlier decision: a
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

**A rule is made from the row, not retyped.** The third icon in a transaction's actions cell links to
`import_matchers#new` with the description, category and counterparty in the query string, and `#new` reads
them through a `prefill_params` that permits those three and nothing else. `trx_type` is deliberately not
among them — `nil` means "any type", which is what a rule generalised from one example nearly always wants —
and neither is `description_is_regex`, an exact description being the more specific claim. The reader still
sees the form, because a rule is a generalisation: it claims rows they are not looking at, and now reaches
backwards as well.

Four details shape it:

- **A link, not a second submit button on the row's form.** Creating a rule fails three ordinary ways — a
  duplicate description, a missing category, a pattern that will not compile — and a row that may not change
  its height has nowhere to report any of them. The form has `#error_explanation` already. An `<a>` is also
  not a member of `form.elements`, so `transaction_row_controller`'s field comparison never sees it, where a
  second submit would need the controller to branch on which button was pressed.
- **It is offered even where a rule already claims the row.** That reads wrong and is not: an exact rule for
  one particular charge that a broad pattern otherwise sweeps up is a documented thing to want, and hiding
  the link on `import_matcher_id` would be the one way to make it impossible. A description that already has
  a literal rule is refused by the uniqueness validation, on the form, where it can be read.
- **It is not offered while a counterparty is waiting to be confirmed.** Leaving the page would discard the
  confirmation, and the name it offered is not a record yet, so there would be no `counterparty_id` to carry.
- **`prefill_params` uses `permit` and a class check, not `expect` and `blank?`.** `params.expect` raises
  when the key is absent, which is the ordinary case of arriving from "New rule", and a hand-written
  `?import_matcher=nonsense` arrives as a `String` — not blank, and it does not answer `#permit`. The
  description's leading and trailing spaces survive the round trip intact, which is the point: a literal rule
  compares them.

Transaction rows are rendered as CSS div-tables (`div-tables.css`), not `<table>` elements.

---

## Authentication

For most of this application's life there was none, and that was written down here as a deliberate
constraint rather than an oversight. What changed is not the threat but the honesty of the accounting:
the file on disk is a complete record of a household's spending, and the only thing between it and
whoever is at the keyboard was the keyboard.

What went in is a gate, and nothing more. No existing table gained a column, no query gained a scope, and
the seven tables the application is about are untouched. The alternative — real multi-tenancy, an owner
on `Account`, scoping threaded through every controller — was rejected because nobody wants it: this is
one household looking at one set of accounts, and per-user data would make the shared view, which is the
whole point, into a feature that had to be built back.

### Built on the generator, and then cut down

`bin/rails generate authentication` rather than Devise or a hand-written concern. Devise is a large
dependency for one sign-in screen. Hand-writing loses more subtly: the generated `Authentication` concern
carries the cookie details that are easy to get quietly wrong — signed, permanent, `httponly`,
`same_site: :lax` — and a hand-copied version of those drifts at the next Rails upgrade with nothing to
say it has.

Half of what it generates was then deleted. The password-reset flow — `PasswordsController`, the mailer,
its two views, the `resources :passwords` route — needs mail, and no SMTP is configured in any
environment; `action_mailer.default_url_options` is still `example.com`. A reset route that emails nothing
is worse than no route: it is a live endpoint that silently does nothing, and it reads to everyone as a
working feature. A forgotten password is `bin/rails users:change_password`, run on the machine the
database is on. The generated Action Cable `Connection` went the same way, there being no channels here.

### The invariant: a Session row means signed in

The second factor is only unskippable because of one rule, and it is worth stating before the mechanism:
**a `Session` row exists only for a fully authenticated sign-in.**

`Authentication#resume_session` looks a user up by `Session.find_by(id: cookies.signed[:session_id])` and
by nothing else. So a row written after the password but before the code is not a step towards being
signed in — it *is* being signed in, and anyone who closed the code screen would already be past it. The
half-authenticated state therefore lives in the Rails session cookie and nowhere in the database:
`session[:pending_user_id]` and `session[:pending_at]`, good for five minutes, which is long enough to
fetch a phone from another room and short enough that an abandoned cookie on a shared machine is worth
nothing. Exactly two methods call `start_new_session_for`, and one of them is the code step.

The alternative — a `Session` row with an `authenticated` boolean on it — was rejected for the same
reason the counterparty confirmation is carried as a name rather than a flag: the safe reading has to be
the default one. A boolean that defaults to false in the schema and true in somebody's later `create!` is
a bypass nobody would notice, whereas a row that simply does not exist yet cannot be misread.

`resource :session` and `resource :totp_challenge`, singular, and the challenge is its own noun for the
reason `counterparty_merges` is: the operation is the noun. `new` and `create` rather than `edit` and
`update`, so that the GET shows what is about to happen and changes nothing.

### Three states, not two

`otp_secret`, `otp_confirmed_at`, `otp_last_used_at` — and `totp_required?` is
`otp_confirmed_at.present?`, which is the only thing the sign-in path asks.

A boolean beside the secret would encode the same three states and say less. What matters is that the
middle one is told apart: someone who opened the enrolment screen, never scanned the QR, and closed it
again has a secret on their row and no way on earth to produce a code for it. Asking them for one at the
next sign-in would lock them out of their own accounts over a step they never took, and it is the one
failure this feature must not have. The timestamp also answers "since when", which is the question worth
asking of a login several people share.

`otp_last_used_at` is what stops a code being used twice. ROTP hands back the timestamp of the step that
matched and takes an `after:` to exclude; without it, a code read over a shoulder or off a proxy log is
good for the rest of its thirty seconds on somebody else's device. One column, one argument, one example.

The pending secret lives on the user row rather than in the session, so that reloading the enrolment
screen shows the *same* QR. A fresh secret each time would invalidate the one already open on the phone,
and the reader could never finish. The cost is that a row can sit half-enrolled for ever; the profile
screen names that state rather than hiding it.

### The secret is encrypted, and the argument against is real

`encrypts :otp_secret`, non-deterministic, nothing ever querying by it.

The case against deserves stating properly, because it is not weak: the keys live in the encrypted
credentials, unlocked by `config/master.key`, which sits on the same disk as the SQLite file and is
symlinked into every worktree by the documented setup. Against somebody walking off with the laptop, this
buys precisely nothing.

It wins on a different threat, and one this repository has already written down. A password digest is
bcrypt: copying the file does not give you the password. A TOTP secret in plain text *is* the second
factor — whoever holds a copy can mint valid codes for ever, and nothing on anyone's screen would ever
say so. And files here do get copied: `.dockerignore` does not exclude `db/*.csv`, Docker's build context
is the filesystem rather than git, and that is already recorded below as something to settle before
deploying. Backups, an `scp` of `storage/`, an image pushed to a registry — encryption is what makes a
copy of the file not a copy of the factor.

The price is paid in CI, which has no `config/master.key`. `config/environments/test.rb` spells out three
keys of its own, marked as deliberately not secret, and Rails merges that config last so the credentials
are never consulted there. This is worth knowing because the failure mode is nasty: encryption keys are
read lazily rather than at boot, so their absence is not a boot error but a green suite locally and a red
one on the first example that writes an encrypted column.

### Recovery is a rake task, not printed codes

`users:create`, `users:change_password`, `users:disable_totp`, `users:list` — prompting for passwords
rather than taking them as rake arguments, which land in the shell history and in `ps`.

Recovery codes were considered and dropped. They cost a table or a serialised column, per-code hashing, a
show-once screen, a consumption path, a "three left" indicator, and specs for all of it. What they buy is
recovery *without shell access* — and the person running this has shell on the machine the database is
on. `bin/rails users:disable_totp` is the same recovery with none of the surface.

What is given up should be recorded plainly, because it is the trigger to revisit: a locked-out household
member cannot recover themselves, and must wait for whoever has the terminal. And if this is ever
deployed somewhere the household does not own, the rake task needs SSH — a strictly larger privilege than
a printed code, at which point codes become the right answer rather than the elaborate one.

Two smaller decisions in the same family. Changing a password destroys the user's *other* sessions and
says how many, because signing the other devices out is the point of changing a password and a change
that leaves them signed in has not done what the reader thought. And turning the second factor off asks
for the current password in the same form as the button: a confirmation stops a misclick, and what this
needs to stop is somebody else at your desk.

### The screens, and the two that are not screens

`/profile` is the hub, and it deliberately does **not** open with `show_actions`. It is a report about
you rather than a record — there is nothing on it to Edit as a record and nothing to Destroy — so it
follows the forecast pages rather than the five Show screens. The two form screens under it, enrolment
and password change, *do* carry `form_actions`, and `form_actions_spec.rb` grew from ten screens to
twelve accordingly. That was the convention asserting itself rather than a concession to it.

The enrolment QR is inline SVG built on the server by `TotpEnrolmentsHelper#qr_code_svg`. An `<img>` to
a generated file would mean writing a provisioning URI — a secret — to disk and then having to clean it
up; a client-side QR library would mean a JavaScript build step this application does not have. One
trap for whoever touches it: rqrcode's `standalone: false` looks like the option for suppressing the XML
declaration and is not, because it drops the enclosing `<svg>` as well and leaves a bare `<path>` that
draws nothing. The declaration is cut off afterwards instead.

The menu bar is hidden entirely while signed out — every item on it would bounce straight back to the
sign-in screen — and gained the reader's own address and Sign out at its far end. That needed
`display: flex` on the list, because Pure lays horizontal menu items out as `inline-block` and
`margin-left: auto` does nothing to one of those.

### A background fetch gets 401, not a redirect

The one place the gate could have broken something silently. The transaction list pages itself with
`get(url, { responseKind: "html" })`; a 302 is followed by `fetch` transparently, so the list would
receive the sign-in page as a 200, find no rows in it, and simply stop advancing — a statement that ends
early, with nothing said.

`request_authentication` therefore answers `head :unauthorized` with the sign-in URL in
`WWW-Authenticate` for `request.xhr?` and Turbo Stream requests, and redirects otherwise. That is not an
invention: `@rails/request.js` already reads that header and sends the browser there itself, so the
reader lands on the sign-in screen and no JavaScript in this application had to learn anything. The 401
also writes no `return_to_after_authenticating`, which is right — a fragment of rows is not somewhere to
come back to.

Two things nearby that look like they need work and do not. `/up` needs no exemption, because
`Rails::HealthController` descends from `ActionController::Base` rather than from `ApplicationController`
and never sees the filter. And `filter_parameter_logging.rb` needed no additions: `:passw` catches the
password fields, `:otp` catches both `otp_secret` and the `otp_code` parameter, `:email` catches
`email_address`. Both are asserted or stated rather than left to be rediscovered.

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

`ForecastDataBuilder` is its counterpart for the forecast, and separate from it on purpose:
`AccountTrxDataGenerator` assigns no categories at all, pins its transactions to the account's opening
date rather than to the month under test, and is shared with `data:create_sample_data` — bending it to
suit would have risked the import specs for no gain. The builder places a history relative to a `today`
the spec supplies: six months of the weekly shop, a monthly direct debit that steps up, a quarterly
bill, a subscription cancelled a year ago, a card payment, some uncategorised spending and a salary.

It leaves balances unset, which the import fixtures cannot. `balance_pence` is nullable and the forecast
never reads it, so skipping the running total keeps `Transaction#sequence` and its `ImportError` out of a
fixture that has nothing to do with importing.

`Forecast::Month` takes `today:` as an argument rather than reading the clock, which is why no forecast
spec freezes time: each one states the situation it is testing instead.

The suite creates the categories it needs itself, via `REQUIRED_CATEGORIES` in `spec/rails_helper.rb`.
It deliberately does not seed from the real statement files: those are gitignored, so depending on them
would make the suite unrunnable on a fresh clone and in CI. One trap that constant sets: it is created in
a `before(:suite)`, *outside* the per-example transaction, so Shopping, Travel and Utilities exist in
every forecast spec and appear as extra lines at zero. They add nothing to a total, but a spec counting
rows has to expect them — and a factory for a category named "Utilities" would collide with the one
already there, which is why the regular-payments factory is named `:subscriptions_category`.

System specs drive a real Chrome through Capybara. The browser locale is pinned to `en_GB` via the
`LANGUAGE` environment variable. Displayed dates no longer depend on it, but a date *field* is drawn by
the browser in its own locale, and a spec filling one in types into whatever order that produces — day
first in the UK, month first on a US-defaulted CI runner.

CI runs Brakeman, importmap audit, RuboCop and the full suite, with the system specs headless.

---

## Deployment

The application is set up to run on **one DigitalOcean droplet, deployed with Kamal**. It is used a
couple of times a week by a household, the database is a few megabytes, and the whole of the traffic
would fit in the margin of error of anything larger. The shape of the deployment follows from the
database being SQLite on local disk, which is a decision made long before there was anywhere to deploy
to.

It is deployed and running at **accounts.peterbell.org.uk**, on a 1GB droplet in London, behind a
Let's Encrypt certificate that kamal-proxy obtained and renews by itself. The database carries the real
history — 233 accounts, 2,626 transactions, 236 rules — and is replicated to Cloudflare R2 continuously.

### Why a plain VM, and not Azure's container hosting

The cheap managed ways to run a container — Azure App Service for Containers, Azure Container Apps, and
the equivalents elsewhere — give persistent storage as a network share. On Azure that is Azure Files,
which is SMB. SQLite's locking is built on POSIX file locks and its `fsync` guarantees; over a network
share those are not honoured faithfully, and the failure is a corrupted database rather than an error at
the time. That rules out the entire class of service, and what remains on Azure is a VM — which is the
droplet again, with a more elaborate console and roughly twice the bill.

The same reasoning would be void the moment the database moved to Postgres, and that is the honest
statement of the trade: SQLite buys a deployment with one moving part and no database server to run, and
costs the ability to use hosting that assumes the data lives somewhere else.

### Why Kamal, and not Dokku

Dokku was the alternative considered. It would work, and it offers `git push` deploys, which Kamal does
not. It lost on the same criterion the rest of this document keeps applying: it is a second system to
own. Dokku has its own release cycle, its own Let's Encrypt plugin and its own persistent-storage plugin,
and adopting it means discarding the Kamal scaffolding the Rails generator already produced — a
`Dockerfile`, a `config/deploy.yml`, `.kamal/secrets`, and Thruster in front of Puma. Kamal installs
Docker on the host itself and its proxy obtains certificates without being asked. There was more to
maintain on the Dokku side and nothing on the end of it that this application wanted.

### The storage volume is a host path, on purpose

`config/deploy.yml` mounts `/var/lib/our-accounts/storage` rather than the named Docker volume the
generator suggests. All four production SQLite databases live there, as does Active Storage's local
service. A named volume would work for the application and be useless for everything around it: the
database could not be replicated by a second container without going through Docker, and could not be
copied onto the machine by hand at all. The container runs as uid 1000, so the host directory is owned to
match — a detail that fails as a permission error on first boot if it is missed.

### Backups are continuous, not nightly

A single machine holds the only copy, so **Litestream runs as a Kamal accessory**, mounting the same host
directory and streaming the write-ahead log to Cloudflare R2. It replicates `production.sqlite3` alone.
The cache, queue and cable databases are derived state that Rails rebuilds from empty, and restoring a
stale copy of them would be worse than not having one.

Continuous replication rather than a nightly `sqlite3 .backup` to object storage, which was the
alternative: the cron job is a thing living outside Kamal that nobody would notice had stopped, and its
granularity is a day, against a database whose whole content is hand-entered judgement that would have to
be re-entered. Streaming the WAL is the cheaper option in the only currency that matters here, which is
attention.

The restore path is deliberately ordinary — pull a copy out of the bucket into the same directory, look at
it, and move it into place — because the day it is needed is not a day to be learning it. It has been
walked once, deliberately: `litestream restore` into a scratch file inside the running accessory, which
already holds the credentials, then counting rows in the result. It returned the same 233 accounts, 2,626
transactions and one user as the live database, and passed `pragma integrity_check`. An untested backup is
a belief rather than a backup, and this one has been tested exactly once, which is the minimum.

Replacing the database underneath a running replica is worth knowing about, because it happened during
the first deploy and could easily have been fumbled. The app was booted with an empty database before the
real one was copied in, so the R2 replica held a lineage belonging to a database that no longer existed.
Litestream handled it: on restart it logged `detected database behind replica`, fetched the latest file,
and uploaded the whole new database as a fresh transaction. Nothing had to be cleared out of the bucket.
The local `.production.sqlite3-litestream` metadata directory *did* have to be removed along with the old
database, though — it belongs to the file it sits beside, not to the replica.

### Production got its data by copy, not by seed

`AccountSeeder` can rebuild an account from the statement CSVs, and that is how a development database is
made. Production was not built that way. The seed reproduces the account, the derived rules and the
imported transactions; it cannot reproduce the hand-assigned categories and the merged counterparties,
which exist only in the database and are the accumulated work the application is for. So the development
database was copied up with `sqlite3 .backup` and put in place as `production.sqlite3`. `db:prepare`,
which `bin/docker-entrypoint` runs on every boot, then found a populated database, applied the pending
migrations and skipped the seed — which is also why excluding the CSVs from the image costs nothing.

This works only because there is one `config/master.key` for every environment: the `encrypts`-ed
`otp_secret` column decrypts unchanged, so the household's existing authenticator enrolments continue to
work rather than everyone being locked out on the first sign-in. It is the reason the copy was preferred
to starting empty, and the thing to check first if a sign-in fails after a move.

**One step is not optional and is easy to miss.** A database copied from development records
`development` in `ar_internal_metadata`, and `db:prepare` refuses to migrate a database last used in
another environment — `ActiveRecord::EnvironmentMismatchError`, raised in the entrypoint, before Puma
starts. The row has to be updated to `production` on the copy before it is uploaded. The refusal is
correct behaviour and worth keeping; it exists to stop someone migrating their development database by
accident, and the failure it produces here is loud and immediate rather than subtle.

### Three things the image build had wrong

The generated `Dockerfile` had never been built. Two of its three faults were silent, which is why they
are recorded here rather than fixed and forgotten — and all three were found by building the image and
looking inside it, which is the part of this section that has actually been exercised.

**It could not get as far as installing the gems.** The `Gemfile` pins the Ruby version by reading
`.ruby-version` — a deliberate constraint, listed below — but the Dockerfile copied only `Gemfile` and
`Gemfile.lock` before running `bundle install`, so bundler refused to parse the Gemfile at all. This one
failed loudly and immediately, and is the reason the other two had gone unnoticed: nothing had ever got
past it to observe them.

**Pure CSS was missing from the built image.** `config/initializers/assets.rb` puts `node_modules` on
Propshaft's asset path for the two `@import`s at the top of `application.css`, `.dockerignore` excludes
`node_modules`, and the generated `Dockerfile` had no Node, no Yarn and no `yarn install`. So
`assets:precompile` ran with nothing to resolve those imports against, and Propshaft does not complain
about an import it cannot find. The deployed site would have rendered with the fallback vertical menu and
unstyled tables, and read as a stylesheet someone had broken rather than a missing dependency. The build
stage now installs Node and runs `yarn install` before precompiling. Debian's packaged Node is old and
that is fine — nothing executes JavaScript at build time, and Yarn is only being asked to unpack one CSS
package.

**The statements would have been pushed to a registry.** `.dockerignore` now excludes `db/*.csv` and
`db/*.xlsx`. This was noted as a thing to settle before deploying, and settling it means the production
seed finds no source files and reports that it is not seeding — which is correct, given the paragraph
above.

### The droplet has 2GB of swap it was not born with

A $6 droplet is 1GB of RAM and no swap at all. A deploy peaks three things at once — Docker unpacking an
image, `db:prepare` running migrations, and Puma booting — and with no swap the kernel's answer to a
momentary overshoot is to kill something rather than page it out. A 2GB swapfile costs 2GB of a 22GB disk
and converts a hard failure into a slow moment. `vm.swappiness` is set to 10, so it stays emergency
headroom rather than somewhere the application gets paged out to routinely.

### What the deployment does not have

No staging environment, no deploy from CI, and no `WEB_CONCURRENCY`: one Puma process with three threads,
with Solid Queue's supervisor inside it via `SOLID_QUEUE_IN_PUMA`. Deploys are run by hand from a
developer's machine, which also builds the image, so the droplet never compiles anything. All of that is
appropriate to a household application used twice a week and would be wrong for almost anything else.

---

## Deliberate constraints

- **No JavaScript build step.** Importmap and Propshaft serve assets directly. Adding a bundler would
  buy nothing here and would cost the ability to edit a controller and reload.
- **No `bin/dev` or `Procfile.dev`.** With no asset build to watch and solid_queue running only in
  production, foreman would supervise a single process while costing the interactive debugger, whose
  stdout would no longer be a TTY. `bin/rails server` is the whole story. Worth revisiting if
  development ever gains a second process, such as `bin/jobs`.
- **The Gemfile pins the Ruby version** by reading `.ruby-version`, so a shell on the wrong Ruby fails
  with an explicit message rather than reporting the bundle's gems as missing. The cost is that anything
  running `bundle install` against a partial copy of the repository has to bring `.ruby-version` with it;
  the `Dockerfile` copies it alongside the `Gemfile` for that reason.
- **No public sign-up, and no password reset by mail.** Users are made from a rake task. There is no
  SMTP anywhere and no host worth putting in a reset link, and an endpoint that emails nothing is worse
  than the absence of one.
- **Statement data never enters the repository, and no longer enters the image.** `db/*.csv` is
  gitignored and the identifying strings live in encrypted credentials. `.dockerignore` excludes them
  too, which is a separate exclusion and has to be: Docker's build context is the filesystem rather than
  git, so without it a locally built image would bake the statements in and push them to the registry.

---

## Where it stands

Working: the account model, both import forms and the screen that drives the routine one, the
categorisation rules and their per-transaction
corrections, the category and counterparty screens with their roll-ups, the rules screens, the CSV
analysis screen, transaction CRUD over Turbo, the monthly forecast and its workings pages, seeding
that rebuilds a development database end to end, and a sign-in — password, then a code from an
authenticator app for anyone who has set one up.

Gaps the sign-in opened, none of them urgent and all of them recorded rather than discovered later:

- **No recovery codes**, so being locked out means finding whoever has a terminal. The argument for the
  rake task is above, and it rested on the machine being the user's own. **The deployment has removed
  that premise.** The terminal is now `kamal app exec` against a rented droplet, which needs the deploy
  credentials, and those are a strictly larger privilege than a printed code would be. Worse, it is held
  by one person: whoever can deploy is the only person who can rescue anyone, including themselves. This
  is the gap on this list most likely to need closing next, and nothing in the code will prompt it.
- **Nothing expires a session.** The cookie is permanent, and only signing out, changing a password or
  deleting the row ends one. There is no idle timeout and no maximum age.
- **No record of sign-ins** beyond the `Session` rows themselves. Nothing says where an account has been
  used from, or when it last was, so a session nobody recognises would have to be noticed rather than
  reported.
- **It is deployed.** Both of the things deploying was blocked on are settled — the Kamal configuration
  is filled in and the image no longer carries the statements — along with a third that nobody had found
  because the image had never once been built: it could not install its gems. The application now runs at
  `accounts.peterbell.org.uk` with the real history in it, and the restore path out of R2 has been walked
  once and produced a matching database. See **Deployment** above. This sharpens the recovery-code
  question two bullets up, which was argued on the assumption that the machine was the household's own,
  and that assumption no longer holds.

The application no longer has a step that has to be done from a terminal. Loading a statement was the last
one, and closing it was worth doing because the categorisation behind it is real: against a year's actual
downloads the derived rules categorise about 64% of transactions automatically, and 85% within the window
that was analysed by hand.

What the import screen still does not do:

- **Nothing undoes an import that succeeded.** A file that loaded correctly but was the wrong file has to
  be unpicked by deleting rows by hand. Atomicity covers the file that fails, which is the more likely
  accident, and an "undo this import" would need a record of which rows came from which run — a schema
  change, not worth making before there is evidence the mistake happens.
- **A long import blocks its request, silently.** About five seconds for a 2,626-row statement, which is
  the largest file in evidence; a month's download is a few hundred rows. There is no progress indication
  beyond the browser's own. A background job is the answer if that becomes uncomfortable, and it is a
  larger change than it looks, because `solid_queue` only runs in production here.
- **A missing period cannot be detected where the layout has no balance column** — see the note beside
  `credit_sign` above. Nothing on a Barclaycard-style account will notice a month that was never loaded.
- **Nothing recomputes the balances of rows after an insertion point.** A file that fits badly is refused
  rather than merged, which is the safe half of the same problem; the unsafe half — a file loaded into the
  middle of an account whose later balances then become stale — is prevented only because the balance
  check refuses it first.

**Prediction now exists; analysis of the past barely does.** The forecast answers "what will this
month cost, and how much of it has gone", which was the point of the application. What it does not do is
look backwards: there are no charts, no totals by category over a period, no comparison between one period
and another, and no record of how past forecasts actually did beyond recomputing them a month at a time.
What does exist is two per-category cuts through the history, both in service of something else: the
counterparty breakdown on a category's Show screen — who it was spent with, all-time, largest first — and
the payee list behind the regular-payments method, which reports what each one last cost and when it was
last seen. Both are useful readings and the obvious place to grow the rest, but each is a single cut over
no chosen period; nothing aggregates a category by month, and nothing compares two periods.

Gaps the forecast opened, all of them visible rather than silent:

- **A recurring series split by a counterparty added part-way through its history is not recognised.**
  The payee is grouped by counterparty where it has one and by description where it has not, so the two
  halves can each fall below the two occurrences a cadence needs. It now fails in the open — both halves
  are listed, each saying it was seen once — and there are two remedies rather than none: merge the two
  counterparties, which carries any hand-set frequency with it, or set a frequency on each half.
- **Refunds are ignored**, so averages read very slightly high — see the reasoning above.
- **A category created after the transactions it should cover reads low**, being averaged over months of
  zeroes. The workings page shows the zeroes and `forecast_months` is the remedy, but nothing warns.
- **Nothing prunes a frequency whose payee has gone.** The ruling is listed, saying it is doing nothing,
  but only for a reader who goes and looks; nothing sweeps them up and nothing counts them.
- **Nothing warns when a hand-set frequency is being contradicted by the history.** The workings page and
  the category screen both say what the history would have guessed, so it can be seen, but a ruling that
  has quietly become wrong — or quietly become redundant — raises no flag anywhere.

Smaller ones elsewhere: nothing **suggests** which counterparties to merge, so the duplicates are found by
eye, and the accounts index renders raw ISO dates while the show page renders localised ones.

Two the rule-by-example work opened, both of them "only ever more, never fewer":

- **Nothing de-applies.** Narrowing a rule, or deleting it, leaves the rows it already claimed exactly as
  they are, still pointing at it. Doing this properly means deciding what an un-applied row reverts *to*,
  which is a different question from applying one.
- **A literal rule does not take rows off a regex rule.** `in_match_order` gives a literal precedence at
  import time, but one created afterwards leaves the pattern's rows where they are, the candidates excluding
  anything already claimed. And there is no preview: the rules index cannot say how many existing
  transactions a rule would catch before it is saved, which would be one candidate query per rule with the
  regex ones unable to go into SQL.

One the two changes make together: **applying a rule can re-key a payee out from under a hand-set
frequency.** `PaymentSchedule#payee_key` is `counterparty_id || description`, matching how
`Forecast::RegularPayments` groups, so a ruling made against a payee that had no counterparty is held by its
description. A rule that names a counterparty then assigns one to every row it claims, and the detector
starts grouping them by that id instead — leaving the ruling applying to nothing. It is the hazard already
recorded above for recategorisation, but a rule reaching backwards is a much readier way to trigger it,
because it moves a whole payee's history at once. It is visible rather than silent: the category screen goes
on listing the ruling and saying it is doing nothing.

One noticed while checking whether an update could safely re-assert a rule over rows it already owns: **a
hand edit through the transaction row does not clear `import_matcher_id`.** `transaction_params` permits
`category_id` and nothing nulls the matcher, so a row whose category was corrected by hand still points at
the rule that got it wrong. Nothing depends on it today — `RuleApplication` reads the *category* to decide
what to leave alone, not the matcher — but it makes "which rule categorised this" only approximately true.

**The index `Transaction#sequence` wanted now exists.** `transactions (account_id, date)` was added with
the import screen: `#sequence` runs `account.transactions.where("date <= ?", date).order(:date, :day_index).last`
**once per imported row**, and scanning a growing table 2,626 times is tolerable from a terminal and not
tolerable inside a request. What it left behind is the opposite question, recorded in TODO.md:
`index_transactions_on_account_id` is now a strict prefix of the composite one and earns nothing it does not,
but the composite is wider and an import writes a few thousand rows at a time, so dropping the cheaper index
deserves a measurement rather than an assumption. `RuleApplication#candidates` still wants one of its own: it
filters on `(account_id, category_id, import_matcher_id)`, of which only the three single-column indexes
exist, though it runs once per rule saved rather than once per row imported.

One newly opened: **a merged-away counterparty can be resurrected.** `AnalysisImporter#counterparty_for`
looks one up by name and creates it when absent, so re-running the analysis import recreates a name that a
merge removed, for any description that does not already have a rule; the guard skipping descriptions the
account already has a rule for is what limits the damage. Typing the old name into a transaction row and
confirming it now does the same thing, though deliberately rather than behind the reader's back. Fixing
either properly means an "absorbed into" pointer and a schema change, which was not worth adding before
there is experience of whether it happens in practice.

One trap worth recording for whoever writes the next migration: **Rails 8.1's schema dumper sorts columns
alphabetically**, unconditionally. `ImportColumnsDefinition::CSV_HEADERS` used to be derived from
`attribute_names`, which follows the table's physical column order — so the first migration run under 8.1
silently reordered the layout of every CSV the application writes, and broke the CSV analysis system spec.
`CSV_HEADERS` is now spelled out by hand, with a spec asserting it still names exactly the `_column`
attributes the table has.

Loading a statement is a screen. What remains at the command line is form A and the work either side of
it — `import:analysis` to derive the rules from a hand-analysed spreadsheet, `import:categorise` to apply
its labels over the top, and `db:seed` to run the whole chain through `AccountSeeder`. All three are
one-off or occasional, which is why they have not earned screens of their own.
