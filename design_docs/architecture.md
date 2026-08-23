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
`SQ *` and `PAYPAL` as payees. So suggestions were left out and the set is always chosen by hand.

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

Conventional Rails: eight controllers, ERB views, no client-side framework.

**Rules are nested under the account.** `ImportMatchersController` lives at
`/accounts/:account_id/import_matchers`, and `account_id` is deliberately absent from its permitted
parameters — the account comes from the route, so a rule cannot be filed against the wrong one. The rule
form sets `url:` explicitly, because `form_with(model: [account, matcher])` would derive
`bank_account_import_matchers_path` from the STI subclass and the route is nested under `:accounts`.

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
  visible there would be nothing left to press. Its `title` carries the instruction — naming what the next
  press will create — because the error itself can only be a tooltip on the field.

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
`Manage Import Rules` moved up into the strip because it acts on the account rather than on the list.

This is also why `.pure-button-error` is defined in `application.css`. Pure ships only the primary
variant, so the delete buttons throughout the app — the transaction rows, the rules list, and now Destroy
— had been asking for a class that did not exist and rendering as ordinary grey buttons.

The forecast's own pages deliberately do **not** use the strip. `show_actions` requires an edit path and
a destroy path, and a forecast page is a report about a month rather than a record: there is nothing to
edit as a record and nothing to delete. They open with a plain Back link instead, in the same position.

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
corrections, the category and counterparty screens with their roll-ups, the rules screens, the CSV
analysis screen, transaction CRUD over Turbo, the monthly forecast and its workings pages, and seeding
that rebuilds a development database end to end.

The gap that matters:

- **Form B has no UI or route.** `FileImporter` is only ever invoked from `AccountSeeder` and from its
  spec. Loading a new statement means dropping into `bin/rails runner`. This is the obvious next piece of
  work, and it is now a much more attractive one, because the categorisation behind it is real: against
  a year's actual downloads, the derived rules categorise about 64% of transactions automatically, and
  85% within the window that was analysed by hand.

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
eye; a rule cannot be created from a transaction you are looking at, so its description has to be retyped;
and the accounts index renders raw ISO dates while the show page renders localised ones.

One worth doing next time a migration is written: `Transaction#sequence` runs
`account.transactions.where("date <= ?", date).order(:date, :day_index).last` **once per imported row**,
and there is no index on `(account_id, date)` — so a 2,626-row import scans a growing table 2,626 times.
It was left alone here only because it has nothing to do with forecasting.

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

Until form B gets a UI, the entry points are rake tasks — `import:analysis` to derive the rules,
`import:categorise` to apply the hand labels, and `db:seed` to run the whole chain through
`AccountSeeder`.
