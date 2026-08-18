# our-accounts

A personal finance tool for tracking household expenditure across several bank and credit-card accounts.

You download statements from your bank's website, load them in, and the application files each
transaction under a category — Groceries, Utilities, Travel — so you can see where the money actually
goes. It learns the categories from work you have already done: point it at a statement you once
categorised by hand in a spreadsheet, and it derives rules from that and applies them to everything you
import afterwards.

It is built for one household. There is no login, no user accounts, and the data lives in a SQLite file
on your own machine.

> **Status: usable, but unfinished in one important way.** Loading a statement has no screen yet — it is
> a command you type. Everything downstream of that works. See [What isn't built yet](#what-isnt-built-yet).

---

## Contents

- [Before you start](#before-you-start)
- [First-time setup](#first-time-setup)
- [Running it](#running-it)
- [The screens](#the-screens)
- [Setting up a new account](#setting-up-a-new-account)
- [Teaching it your categories](#teaching-it-your-categories)
- [Importing a statement](#importing-a-statement)
- [Correcting categories](#correcting-categories)
- [Command reference](#command-reference)
- [When something goes wrong](#when-something-goes-wrong)
- [What isn't built yet](#what-isnt-built-yet)

---

## Before you start

You need:

- **Ruby 4.0.6.** Managed by rvm; `.ruby-version` selects it. If your shell is on a different Ruby the
  application refuses to start with a clear message rather than failing obscurely.
- **yarn**, for the one CSS package the interface uses.
- **Google Chrome**, only if you intend to run the test suite.

Your bank statements are CSV files you download yourself. They are never committed to the repository and
never leave your machine.

## First-time setup

```sh
bundle install
yarn install
bin/rails db:prepare
```

Then start it (see below) and visit <http://localhost:3000>.

If you have statement files and the matching credentials configured, `bin/rails db:seed` will build an
account and its whole history in one step — see [Command reference](#command-reference).

## Running it

```sh
bin/rails server
```

Then open <http://localhost:3000>. Stop it with `Ctrl-C`.

There is no `bin/dev` — `bin/rails server` is the only command you need.

---

## The screens

Four items in the navigation bar:

| Screen | What it is for |
| --- | --- |
| **Accounts** | Your bank and credit-card accounts, and the transactions in each |
| **Categories** | The list of spending categories |
| **Counterparties** | The suppliers and vendors you deal with, and everything you have spent with each |
| **Input Columns Definition** | How to read each institution's CSV layout |

The rules that categorise transactions are reached from the account they belong to, rather than from the
navigation bar — see [Import rules](#import-rules) below.

The menu bar stays at the top of the window wherever you have scrolled to, so moving to another screen
never means scrolling back up first.

Every date you are shown is written the same way throughout — `1-Jan-23`. The one exception is a date
you can type into, which your browser draws in its own style.

### Accounts

The landing page lists your accounts with their number, sort code, opening date and opening balance.
**Show this account** opens the account, where you get the details at the top and the transactions
below, newest first: date, description, category, counterparty, amount, and the running balance after
that transaction. Money out is red, money in is green.

The details at the top spread across the width of the window — three to a line on a wide screen, so an
account fits on two lines — and fold down to one field per line as the window narrows.

An account soon holds thousands of transactions, so the list shows a window of twenty at a time inside
its own scrolling box, with the column headings staying put above them. Scroll to the bottom of the box
and the window slides on to older transactions; scroll back up and the earlier ones return. Only twenty
rows are ever on the page, however long you spend scrolling, so it stays quick.

Transactions you have already scrolled past are kept in the browser's memory, so coming back to them is
instant and does not go back to the server. Anything you had changed but not yet saved — a category you
picked from a dropdown, say — is still there when you scroll back to it.

To move somewhere further back, use the buttons above the list rather than scrolling for a long time:
**« Month**, **« Week** and **« Day** step the list backwards, and **Day »**, **Week »** and **Month »**
step it forwards again. The line to their right tells you where you are — *Showing transactions on or
before 13-Dec-24* — and once you have moved away from the present, a **jump to latest** link brings you
straight back. Buttons that would take you past the beginning or end of the account are greyed out.

You can edit a transaction's category straight from the list using the dropdown in its row. A save
button appears at the end of that row as soon as you change something, and goes again if you put it
back as it was, so at a glance you can see which rows are waiting to be saved. Each row also has a
delete button; both are icons, and hovering over either one says what it does. **Add New Transaction**
adds a row you can fill in by hand, for anything that did not come from a statement — it offers its save
button straight away.

The **Counterparty** column names the supplier, where one is known. Start typing in it and your
existing counterparties are offered as completions; pick one and save, and the transaction is linked to
it. The small icon beside the name opens that counterparty's own page. Clearing the field unlinks it.

A name that is not already a counterparty is **refused**, and the field turns red rather than the row
saving. That is deliberate: counterparty names imported from statements are already untidy, and quietly
creating a new one from a typo would make it worse. Create it on the Counterparties screen first. Case and
stray spaces do not matter — `octopus energy` finds `Octopus Energy`.

### Categories

A flat list of names with optional descriptions — "Groceries", "Utilities", "Dine Out". Categories are
shared across all accounts. You can add, rename and delete them freely.

The list is alphabetical by name to begin with. Click either column heading to reorder it, and the same
heading again to reverse it; an arrow marks which column the order is on. Sorting by description brings
the ones you have not described yet together.

Most of your categories will be created for you the first time you load a hand-categorised statement,
so it is usually easier to do that first and tidy the list afterwards than to type them all in.

### Counterparties

A counterparty is whoever a transaction was with — Tesco, Octopus Energy, the water company. Giving one a
record of its own means every transaction with that supplier is linked together, across all your accounts:
the current account and the credit card you sometimes paid them with show up on one page, with a total.

Not every transaction has one. A one-off purchase, or a description too cryptic to identify, simply has no
counterparty, and that is expected rather than a gap to fill.

The list shows how many transactions each has and how much you have spent with it, and starts in
alphabetical order so you can find the one you meant. Click any column heading to reorder it, and again to
reverse it.

**Total** is the ordering worth knowing about. Counterparties created by the analysis step are named after
**raw statement text** — `TESCO STORES 2889` rather than `Tesco` — and sorting by total brings the ones
where renaming actually pays off to the top. Renaming is the main thing you will do here.

Names are tidied as they are saved: surrounding and doubled spaces are removed, so a name always matches
itself when you type it into a transaction row. Two counterparties cannot differ only in case, which would
leave you guessing which of `TESCO` and `Tesco` a transaction had been linked to.

Deleting a counterparty keeps its transactions; they simply stop naming anyone.

### Import rules

These are what categorise a transaction automatically, and they belong to a particular account — a rule
learned from your current account should not be applied to a credit card whose statements read differently.
So they live under the account: open an account and follow **Import rules for this account**.

Each rule says: when a transaction's description looks like *this*, give it *this* category and *this*
counterparty.

| Field | Meaning |
| --- | --- |
| **Description** | Required. The text to look for, exactly as the statement writes it |
| **Treat as a pattern** | Match a regular expression anywhere in the description instead of the whole thing, so `AMAZON` catches `AMAZON* 204-813115` |
| **Transaction type** | Restrict the rule to one type — `DD`, `DEB`. Leave blank to match any, which is usually what you want |
| **Category** | Required. This is what the rule is for |
| **Counterparty** | Optional. Leave it as *none* for a vendor you cannot identify |

When more than one rule matches, **an exact description always beats a pattern**. So you can have a broad
`AMAZON` pattern and still write an exact rule for one particular Amazon charge that belongs elsewhere.

The list shows a **Matched** count against each rule: how many transactions it has actually caught. A rule
matching nothing usually has a typo, or trailing spaces in its description — the list marks those with ⚠,
because a literal rule compares the description exactly, spaces included.

A pattern that is not a valid regular expression is refused when you save it, rather than failing part-way
through your next import. So is an empty description: ticked as a pattern it would match every
transaction and quietly categorise everything nothing else caught, and left as plain text it could never
match at all.

Most rules are created for you in bulk by [Teaching it your categories](#teaching-it-your-categories).
This screen is for correcting those and adding the ones it could not work out.

### Input Columns Definition

Every bank lays its CSV out differently, so the application needs to be told, once per account, which
column holds what. This screen is where you describe that.

You do not have to work it out by reading the file. The right-hand side of the form has an **Analyze
Sample CSV** panel: choose a statement you have downloaded, press **Analyze File**, and it shows you the
columns it found. You then drag each one into the matching field on the left — drag the column that
holds the date into **Date column**, and so on.

The fields worth understanding:

| Field | Meaning |
| --- | --- |
| **Header** | Tick if the first line of the file is column names rather than a transaction |
| **Reversed** | Tick if the newest transaction is at the top of the file (Lloyds does this) |
| **Credit sign** | Choose *Negative* if the bank writes spending as a positive number (Barclaycard does this) |
| **Date format** | How dates are written, e.g. `%d/%m/%Y` for `31/12/2024` |
| **Debit / Credit column** | Use these when money in and money out are in separate columns |
| **Amount column** | Use this instead when there is a single signed amount column |

Fill in **either** the debit and credit columns **or** the amount column, never both — the form will
tell you if you get this wrong.

---

## Setting up a new account

1. Go to **Accounts** and press **New account**.
2. Choose the type — a current account or a credit card.
3. Enter the name you want to call it, the account number and sort code (cards have no sort code), and
   the opening date and balance.

**The opening balance matters more than it looks.** The application recalculates a running balance for
every transaction and checks it against the balance printed in the statement. If the opening balance is
wrong, the very first import stops with an error rather than loading thousands of subtly wrong rows.

The easiest way to get it right is to work backwards from the statement you are about to load: take the
oldest transaction in the file, and subtract its amount from the balance shown against it. If the file
is newest-first, the oldest transaction is the **last line**.

4. Now go to **Input Columns Definition** and create one for the account, using the sample-CSV panel
   described above.

The account is now ready to accept statements.

---

## Teaching it your categories

This is what makes the automatic categorisation work, and it is a one-off.

If you have previously categorised your spending by hand — a statement exported to a spreadsheet with a
`Category` column added — the application can learn from it. Put that file in the `db/` directory and
run:

```sh
bin/rails "import:analysis[your-analysis-file.csv,Account Name]"
```

It reads the file and does two things: creates any categories it has not seen, and creates one rule per
distinct transaction description, so that `TESCO STORES 2889` is filed under whatever you filed it under.

It tells you what it did, and importantly what it refused to do:

```
Categories created:      28
Import matchers created: 282 against Joint

Skipped 10 descriptions filed under two categories equally often:
  "WATERSTONES" -> {"Dine Out" => 1, "Gifts" => 1}
  "SAINSBURYS PETROL" -> {"Food" => 1, "Car" => 1}
  ...

1 rule created without a counterparty, the description being too short to name one:
  "O2"
```

Where you filed the same shop under two different categories, it takes whichever you used more often.
Where it is an exact tie it makes no rule at all and lists the description, because guessing would be
worse than leaving it to you. You can categorise those transactions by hand afterwards.

It also creates a counterparty for each vendor, named after the description — so those names are raw
statement text, and worth tidying on the [Counterparties](#counterparties) screen. Where a description is
too short to be a name at all (`O2`), you get the rule without a counterparty, which is what the last line
of that report is telling you.

Where the same vendor appears in two spellings that differ only in case — `TWO MAGPIES BAKERY` and
`Two Magpies Bakery`, which real statements do produce, sometimes on the same day — you get **one**
counterparty, named with the tidier spelling, and a rule for each spelling pointing at it. So the vendor
has one page and one total rather than two halves.

Running it again is safe: it creates nothing twice, and any rule you have since retuned by hand is left
exactly as it is rather than being reset to what the spreadsheet said. It counts those separately:

```
Import matchers created: 0 against Joint
Rules already present:   282 (left exactly as they are)
```

**If you have no such spreadsheet**, skip this step. Create your categories by hand on the Categories
screen, import your statements, and categorise transactions from the account screen as you go.

---

## Importing a statement

⚠️ **There is no screen for this yet.** It is a command:

```sh
bin/rails runner 'FileImporter.new(Rails.root.join("db", "statement.csv"), Account.find_by(name: "Joint")).import'
```

Put the downloaded CSV in the `db/` directory first, and use the exact name you gave the account.

A few thousand transactions take a handful of seconds. Transactions that match a rule are categorised as
they load; the rest arrive uncategorised for you to deal with on the account screen.

Then open the account and check the list. The closing balance on the newest transaction should match the
balance on your real statement.

**Do not import the same file twice.** The application will notice — the running balance will not
reconcile and it will stop with an error — but you will then have a half-loaded account to tidy up.

---

## Correcting categories

The rules work on the transaction description, so they treat every `NON-GBP TRANS FEE` the same way. In
practice one might be a holiday and the next a work trip, and only you know which.

Two ways to fix this.

**One at a time, on the account screen.** Change the dropdown in the transaction's row and press the
save button that appears at the end of it.

**In bulk, from your hand analysis.** If your spreadsheet already has the right answer for a period you
have just imported, apply it wholesale:

```sh
bin/rails "import:categorise[your-analysis-file.csv,Account Name]"
```

This matches each row in the spreadsheet to the transaction it refers to and applies your category,
overriding whatever the rules concluded. It reports how many it changed and where it disagreed with the
rules:

```
Categories applied:  47
Already correct:     625
Corrected a rule:    22
No matching trx:     0

Where your analysis disagreed with the rules:
  NON-GBP TRANS FEE     Holidays -> Travel
  MARKS&SPENCER PLC     Food -> Clothing
  ...
```

`No matching trx: 0` is the number to look at — anything above zero means some spreadsheet rows could
not be tied to a transaction, usually because that period has not been imported yet.

Your hand judgement always wins over a rule, and re-running changes nothing.

---

## Command reference

Run these from the project directory.

| Command | What it does |
| --- | --- |
| `bin/rails server` | Start the application on <http://localhost:3000> |
| `bin/rails db:seed` | Build an account and its full history from the statement files in `db/` — account, rules, transactions and hand categories, in one step. Safe to re-run. |
| `bin/rails "import:analysis[file.csv,Account]"` | Learn categories and rules from a hand-categorised statement |
| `bin/rails "import:categorise[file.csv,Account]"` | Apply hand-assigned categories to transactions already loaded |
| `bin/rails console` | An interactive prompt, for anything the screens do not cover |
| `bundle exec rspec` | Run the test suite (needs Chrome) |
| `bin/rubocop` | Check code style |

`db:seed` is the quickest route from an empty database to a working one, but it needs the statement
filenames and account name configured in the encrypted credentials. If you are setting up by hand
instead, follow the steps above in order.

---

## When something goes wrong

**"Your Ruby version is 4.0.0, but your Gemfile specified 4.0.6"**
Your shell is on the wrong Ruby. Run `rvm use ruby-4.0.6`. If it keeps happening in new terminals,
something long-running — your editor, or the desktop session — is passing an old environment down to
them; restarting it, or logging out and back in, fixes it.

**The import stops with `ImportError`**
The running balance did not match the statement. Almost always the account's opening balance is wrong —
see [Setting up a new account](#setting-up-a-new-account). It can also mean you are importing a file
that overlaps one already loaded. Nothing is saved when this happens, so correct the opening balance and
try again.

**Transactions imported but none are categorised**
Either no rules exist yet — run the analysis step — or the rules belong to a different account. Rules
are per-account, so a rule learned on your current account will not categorise card transactions.

**A rule I wrote never categorises anything**
Check its **Matched** count on the rules list. If it is zero, the usual causes are a description with
leading or trailing spaces — a literal rule matches exactly, and the list marks those with ⚠ — or a
**Transaction type** that does not match the statement's. Leave the type blank unless you mean it.

**`db:seed` says it is not seeding anything**
It cannot find the statement files in `db/`, or the credentials naming them are not set. It reports
which file is missing.

---

## What isn't built yet

Being honest about the gaps, in the order they matter:

1. **No screen for importing a statement.** `FileImporter` works and is well tested, but you have to
   invoke it from the command line. This is the most worthwhile thing to build next.
2. **No analysis or prediction.** No charts, no totals by category or by month, no forecasting — which
   is awkward, because that was the point of the application. Everything needed to build it is in place:
   transactions are loaded, categorised and reconciled.
3. **No way to merge two counterparties.** If the same supplier arrived under two descriptions, you get
   two counterparties, and the only way to unite them is to rename one, delete the other, and re-point its
   transactions by hand.
4. **A rule cannot be created from a transaction you are looking at.** Having spotted an uncategorised
   row, you have to go to the rules screen and retype its description rather than saying "make a rule from
   this".

How well the automatic categorisation does depends on how much hand analysis you feed it. Against a
year of real statements with one quarter analysed by hand, roughly two thirds of transactions were
categorised automatically, rising to about 85% within the analysed period.
