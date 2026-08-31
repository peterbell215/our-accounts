# our-accounts

A personal finance tool for tracking household expenditure across several bank and credit-card accounts.

You download statements from your bank's website, load them in, and the application files each
transaction under a category — Groceries, Utilities, Travel — so you can see where the money actually
goes. It learns the categories from work you have already done: point it at a statement you once
categorised by hand in a spreadsheet, and it derives rules from that and applies them to everything you
import afterwards.

It is built for one household. Everyone in the house gets their own sign-in — a password, and an
authenticator app on your phone if you want one — and you all see the same accounts and the same
transactions. Nobody has a private corner of it. The data lives in a single database file on one small
rented machine, backed up continuously — see [Putting it on a server](#putting-it-on-a-server).

> **Status: usable.** Everything you need for the monthly routine has a screen — setting up an account,
> loading a statement, correcting how things are filed, and forecasting what the month will cost. What it
> does not do is look *backwards*: there are no charts and no comparison of one period against another.
> See [What isn't built yet](#what-isnt-built-yet).

---

## Contents

- [Before you start](#before-you-start)
- [First-time setup](#first-time-setup)
- [Running it](#running-it)
- [Putting it on a server](#putting-it-on-a-server)
- [Signing in](#signing-in)
- [The screens](#the-screens)
- [Setting up a new account](#setting-up-a-new-account)
- [Teaching it your categories](#teaching-it-your-categories)
- [Importing a statement](#importing-a-statement)
- [Correcting categories](#correcting-categories)
- [Forecasting a month](#forecasting-a-month)
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
bin/rails users:create
```

The last one asks for an email address and a password, and makes the login you will use. Do it for each
person in the house. There is **no sign-up page**, on purpose: this application is not on the internet
for strangers to find, and a page that lets anyone make themselves an account would be the one thing on
it worth attacking. Until you have run it, the sign-in screen has nothing to let you past — which is why
the setup says so if you start a server with no users yet.

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

## Putting it on a server

It is on one: **<https://accounts.peterbell.org.uk>**. Everybody in the house signs in there the same way
they would have at home, from any phone or laptop, and the certificate renews itself.

It runs on a small rented machine — a £5-a-month DigitalOcean droplet — with the database on that
machine's own disk. Deploying a change is one command from a checkout of this repository:

```sh
bin/kamal deploy
```

That builds the application, sends it up, and switches over to it without dropping anybody mid-request.
`bin/kamal logs` shows what the server is doing, and `bin/kamal console` gives you the same interactive
prompt you would get at home.

**Your statements do not go to the server.** The CSV files you download from your bank stay on your own
machine; the server only ever sees the transactions after you have imported them through the screen.

**The database is copied off the machine continuously.** Every change is streamed to Cloudflare storage
within seconds, so losing the machine loses nothing. That path has been walked once on purpose — a copy
was pulled back out of storage and checked against the live one, and they matched. It is worth repeating
occasionally, because a backup nobody has ever restored is a belief rather than a backup.

**One thing to know.** Now that it is on a server, the way back in for somebody locked out runs against
that server rather than a laptop in the house — see [Signing in](#signing-in). In practice that means the
person who can deploy is the only person who can rescue anybody.

---

## Signing in

Your email address and your password, and that is it — unless you have set up an authenticator app, in
which case it asks for a six-digit code next. Get the password wrong and it says so without telling you
which half was wrong, which is the polite version and also the safe one.

Once you are in, your address is at the right-hand end of the menu bar. That is your own page: it says
whether two-factor is on, and it is where you turn it on, turn it off, or change your password.

**Setting up an authenticator app.** From your own page, choose *Set up an authenticator app*. Scan the
square with 1Password, Google Authenticator, Authy — whichever you use — then type the code it shows you,
to prove it worked. Nothing changes about how you sign in until you have done that last bit, so a scan
that silently failed cannot lock you out. If your phone cannot scan, the same secret is printed
underneath in words.

To turn it off again, go back to your own page and type your password. Asking for the password is
deliberate: without it, anybody walking past your unlocked screen could take it off in one click.

**Changing your password** signs you out of every other device you were signed in on, and tells you how
many. That is the point of changing it.

**If you are locked out** — a lost phone, a forgotten password — nothing on any screen can help you,
which is by design. The way back is a command, run on the machine this is installed on:

```sh
bin/rails "users:disable_totp[you@example.com]"      # lost your phone
bin/rails "users:change_password[you@example.com]"   # forgotten your password
```

The first turns two-factor off so a password alone gets you in, and you can set the app up again
afterwards. There are no printed backup codes to lose.

If it is running on a server, the same two commands are run through Kamal from a machine set up to deploy
it, rather than on the server itself:

```sh
bin/kamal app exec --interactive --reuse 'bin/rails "users:disable_totp[you@example.com]"'
```

Which is worth being clear-eyed about: it means whoever can rescue you is whoever can deploy the
application, and nobody else. In a house where one person set it up, that is one person — so if you are
that person, do not lose your own phone.

---

## The screens

Five items in the navigation bar, plus your own address at the far end:

| Screen | What it is for |
| --- | --- |
| **Accounts** | Your bank and credit-card accounts, and the transactions in each |
| **Forecast** | What this month is likely to cost, and how much of it has already gone |
| **Categories** | The list of spending categories |
| **Counterparties** | The suppliers and vendors you deal with, and everything you have spent with each |
| **Input Columns Definition** | How to read each institution's CSV layout |

The rules that categorise transactions are reached from the account they belong to, rather than from the
navigation bar — see [Import rules](#import-rules) below.

The menu bar stays at the top of the window wherever you have scrolled to, so moving to another screen
never means scrolling back up first.

Whatever you are looking at — an account, a category, a counterparty, a rule, a column layout — the page
for one record reads the same way. It names what you are looking at as its heading, and under that come
the same three buttons, above the record's own details: **Back** to the list you came from, **Edit** it,
and **Destroy** it. Anything particular to that kind of record sits alongside them. **Destroy** is kept
apart at the right-hand end, coloured red, and always asks first, telling you what goes with the record
and what is kept.

Because the heading already names the record, its details do not repeat it: an account's page is headed
*Lloyds Account* and lists the number, sort code and opening figures beneath.

Creating or editing something reads the same way, with the buttons you need to leave the screen in the
same place — under the heading, above the form, never at the bottom of the page. **Back** returns to the
list, and when you are editing, **Show** opens the record as it currently stands, so you can look at what
you are about to change without losing your place. There is no **Destroy** here: to delete something, open
it first. Saving is the button at the foot of the form itself, where you finish filling it in.

The one list with a **Back** button of its own is an account's import rules, because it is the only list
you reach from somewhere else rather than from the menu bar; **Back** there returns you to the account. The
screen that confirms a merge has one too, above the names it is about to fold together, as well as the
**Cancel** beside **Merge** at the foot of it.

Every date you are shown is written the same way throughout — `1-Jan-23`. The one exception is a date
you can type into, which your browser draws in its own style.

### Accounts

The landing page lists your accounts with their number, sort code, opening date and opening balance.
**Show this account** opens the account, headed by its name, with its buttons and details at the top and
the transactions below, newest first: date, description, category, counterparty, amount, and the running balance after
that transaction. Money out is red, money in is green.

Two buttons at the top belong to the account rather than to the list: **Import Statement**, which is how
you load a download from the bank, and **Manage Import Rules**, which is how you tell it where things
should be filed.

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
delete button, and a third that makes an import rule out of the row — see
[Import rules](#import-rules). All three are icons, and hovering over any of them says what it does.
**Add New Transaction** adds a row you can fill in by hand, for anything that did not come from a
statement — it offers its save button straight away.

The **Counterparty** column names the supplier, where one is known. Start typing in it and your
existing counterparties are offered as completions; pick one and save, and the transaction is linked to
it. The small icon beside the name opens that counterparty's own page. Clearing the field unlinks it.

A name that is not already a counterparty is **not created on the first save**. The field turns amber, and
a message above the list says which name it is offering to create and that the rest of your edits to the
row are being held. Save the row a second time and the counterparty is created and linked, and its name is
offered as a completion in every other row from then on; the message goes when you have answered it. The
second save is there because counterparty names imported from statements are already untidy and a typo
should not quietly join them — correct the name before saving again and you are asked about the correction
instead, so nothing is created behind you. Case and stray spaces do not matter — `octopus energy` finds
`Octopus Energy`.

Two names are refused outright rather than offered. For those the field turns **red** rather than amber,
the message says why, and the save button goes away until you change what you typed: a name shorter than
three characters, which is too short to be a name, and the name of one of your own accounts, which already
exists and cannot be a counterparty as well.

The colours are worth knowing apart. **Amber is a question** — the row is asking whether to create
something and waiting for you to say yes. **Red is a refusal** — nothing you can do but change the name. In
both cases the row itself is not saved, but the edits you made to its other columns are still sitting in
the form, not thrown away.

### Forecast

What this month is likely to cost, category by category, and how much of it has already gone. Every line
shows the forecast, what has been spent so far, and what is still to come — with a total at the bottom
that is the number the screen is really for.

**Still to come never goes below zero.** A category you have already overspent simply has nothing left
to come; it does not start subtracting from the rest.

The screen opens on **the last month you have imported transactions for**, which is usually the month
just gone rather than the one the calendar is in: statements arrive in arrears, so opening on the
calendar's month would show predictions with barely a day or two of spending to weigh them against.
Where that month has finished, a **jump to this month** link sits beside the month buttons.

Use **«** and **»** to move a month either way. Going back to a month that has finished swaps the last
column for **Difference**, which is how far the month ran over or under what would have been predicted
for it — the closest thing to a report card the application has.

Clicking a category opens its **workings**: the months an average was taken over, or the individual
bills a category was built from, and in every case the transactions recorded in that category this month
so you can check the figures against what actually happened.

How each category is predicted is set on the [Categories](#categories) screen — or by clicking what the
second column says, which takes you straight to that category's form. See
[Forecasting a month](#forecasting-a-month) for what to choose and why.

### Categories

A flat list of names with optional descriptions — "Groceries", "Utilities", "Dine Out". Categories are
shared across all accounts. You can add and rename them freely.

Opening one shows **who you spent it with**: every supplier a transaction filed under this category names,
how many of those transactions there are and what they came to, with the largest spend at the top. Each
name is a link to that supplier's own page, where the same money is gathered the other way round — every
dealing with them, whichever account paid. Transactions with no counterparty are simply left out; a one-off
purchase not naming anyone is expected rather than something to fix.

Below that are **the rules that file things here** — which account each belongs to, the description it
matches, and the supplier it names, with a dash where it names none. This is also the list to read when a
delete is refused, because those are the rules standing in the way.

Deleting one is refused while any import rule still assigns it, and the message names the rules in the way,
because a rule without a category has nothing left to do. Change or delete those rules first. Otherwise the
delete goes ahead: transactions already filed under the category are kept, and simply stop naming one.

Each category also carries **how it should be predicted**, which is what the
[Forecast](#forecasting-a-month) uses — an average of recent months, its regular payments one at a time,
a figure you enter yourself, or not at all. A new category is set to the average until you say otherwise.
Where you choose the average you can also say **how many months to average over**; leave it empty for six.

Where you choose **its regular payments**, editing the category also shows you every payee it found in
that category: what each one last cost, when it was last seen, how often it comes, and whether it is part
of the forecast — with the reason where it is not. Each one's frequency is a dropdown, so where the
application has read the history wrongly you can simply tell it. See
[Correcting what it found](#correcting-what-it-found).

The list is alphabetical by name to begin with. Click any column heading to reorder it, and the same
heading again to reverse it; an arrow marks which column the order is on. Sorting by description brings
the ones you have not described yet together, and sorting by **Predicted by** groups them by method,
which is the quickest way to see which ones you have not thought about yet.

Most of your categories will be created for you the first time you load a hand-categorised statement,
so it is usually easier to do that first and tidy the list afterwards than to type them all in.

### Counterparties

A counterparty is whoever a transaction was with — Tesco, Octopus Energy, the water company. Giving one a
record of its own means every transaction with that supplier is linked together, across all your accounts:
the current account and the credit card you sometimes paid them with show up on one page, with a total.

Not every transaction has one. A one-off purchase, or a description too cryptic to identify, simply has no
counterparty, and that is expected rather than a gap to fill.

Most of them arrive on their own, named after raw statement text, when you load a hand-categorised statement.
You can add one here with **New Counterparty**, but the usual way is to type the name straight into a
transaction's Counterparty column and save the row twice — see [the transaction list](#accounts).

The list shows how many transactions each has and how much you have spent with it, and starts in
alphabetical order so you can find the one you meant. Click any column heading to reorder it, and again to
reverse it.

**Total** is the ordering worth knowing about. Counterparties created by the analysis step are named after
**raw statement text** — `TESCO STORES 2889` rather than `Tesco` — and sorting by total brings the ones
where renaming actually pays off to the top. Renaming is the main thing you will do here.

Names are tidied as they are saved: surrounding and doubled spaces are removed, so a name always matches
itself when you type it into a transaction row. Two counterparties cannot differ only in case, which would
leave you guessing which of `TESCO` and `Tesco` a transaction had been linked to.

Deleting a counterparty keeps its transactions; they simply stop naming anyone. Note that a name you delete
or merge away can come back: typing it into a transaction row again will offer to create it, as will
re-running the analysis import.

#### Merging duplicates

One payee usually arrives under several names, because the bank cuts its description short: `TESCO STORES
2228` and `TESCO STORES 2889` are one shop, and eleven separate `AMAZON*` entries are one Amazon. Tick them
and press **Merge selected**.

**Or press *Suggest merges* and be handed a shortlist.** Rather than reading a few hundred names yourself,
you get sets that look like one payee, each with a sentence saying why and a **Review** button that opens
the same confirmation described below. Nothing is merged for you — every group still has to be confirmed,
and you can change the name it proposes.

This is the one feature that sends anything off this machine. It asks the Claude API, and what it sends is
your counterparty names and the names of the categories you file them under — **no amounts, no dates, no
account numbers and nothing about individual transactions**. Without a key configured the screen says so and
everything else still works. It is worth knowing that the suggestions are a starting point and not an
authority: it is told that `LNK`, `SQ *` and `PAYPAL` are payment rails rather than payees, and that a shared
first word means nothing, but the last judgement is yours on the confirmation screen.

**On your own machine, sign in with the Claude Code CLI.** Run `claude setup-token`, and export what it
gives you:

```sh
export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...
```

That is all development needs — nothing goes in the credentials file. The token does eventually expire; when
it does the screen reports that the sign-in was refused, and a fresh `claude setup-token` fixes it.

**For a deployed copy, name a provider in the credentials instead.** Some hosts sell access to the same
models, which is worth having if you already pay them for hosting and would rather keep one bill.
DigitalOcean is one; give it a token, its address, and its own name for the model:

```yaml
anthropic:
  auth_token: dop_v1_...
  base_url: https://inference.do-ai.run
  model: anthropic-claude-opus-5
```

Put that in the **production** credentials — `bin/rails credentials:edit --environment production` — rather
than the shared file. The shared one is readable on every machine, so a token left there would have everyone
developing against the deployed copy's account.

The model name differs by provider: the same model is `claude-opus-5` from Anthropic and
`anthropic-claude-opus-5` from DigitalOcean, and giving one provider the other's name fails with an unhelpful
*not found*. If a provider turns out not to support everything this needs, the screen reports what it said
rather than breaking, so trying one costs nothing but the request.

*If you do have an ordinary API key, `anthropic: api_key:` in the credentials still works and takes
precedence — and "Claude API key" and "Anthropic API key" are two names for the same thing.*

You then get a confirmation listing each one with its transactions, its total, and the categories its rules
assign, and a box for what to call the result. **The name can be anything** — it does not have to be one of
the names listed. That is how five `LNK ...` cash-machine entries become a single counterparty called
`ATM`.

Nothing is lost. Every transaction and every rule moves to the merged counterparty; only the spare names
go, and **no category changes** — each rule keeps the one it had.

If the name you choose is already held by a counterparty you did *not* tick, or by one of your own accounts,
the merge is refused and nothing moves. You come back to the same confirmation with everything still ticked
and **the name still as you typed it**, so you can correct it rather than start again.

Read the categories column before you confirm. It is the best clue that a group is *not* one payee: if some
say Food and others Car, you are probably looking at `TESCO STORES` and `TESCO PAY AT PUMP`, which are the
supermarket and the petrol station and should stay apart. The screen warns you when they disagree, but lets
you go ahead — a gym that also runs a café really is one payee under two categories.

Merging cannot be undone, which is why the confirmation shows exactly what is about to move.

### Import rules

These are what categorise a transaction automatically, and they belong to a particular account — a rule
learned from your current account should not be applied to a credit card whose statements read differently.
So they live under the account: open an account and press **Manage Import Rules**, with the account's
own buttons at the top of the screen.

Each rule says: when a transaction's description looks like *this* — and, if you choose, its amount
compares to *this* — give it *this* category and *this* counterparty.

| Field | Meaning |
| --- | --- |
| **Description** | Required. The text to look for, exactly as the statement writes it |
| **Treat as a pattern** | Match a regular expression anywhere in the description instead of the whole thing, so `AMAZON` catches `AMAZON* 204-813115` |
| **Transaction type** | Restrict the rule to one type — `DD`, `DEB`. Leave blank to match any, which is usually what you want |
| **Amount** and **Comparison** | Optional. Restrict the rule to one comparison against the amount — equal to, not equal to, less than, or the others. A purchase is entered as a negative number, e.g. `-7.99`, matching how amounts appear everywhere else. Leave the comparison as *any amount* to match every amount, which is usually what you want |
| **Category** | Required. This is what the rule is for |
| **Counterparty** | Optional. Leave it as *none* for a vendor you cannot identify |

When more than one rule matches, **an exact description always beats a pattern**, and **a rule naming an
amount always beats one that does not**, for the same description. So you can have a broad `AMAZON` pattern
and still write an exact rule for one particular Amazon charge that belongs elsewhere — and you can write
two rules for the same description, one for a specific amount and one with no amount condition as the
default for everything else. That is how to split `APPLE.COM/BILL`, where most charges are a fixed £7.99
subscription and the rest are one-off film or music purchases: one rule for "amount equal to -£7.99" filed
under Subscriptions, and a second rule for the same description with no amount condition, filed under
Entertainment, catching whatever the first one does not.

The list shows a **Matched** count against each rule: how many transactions it has actually caught. A rule
matching nothing usually has a typo, or trailing spaces in its description — the list marks those with ⚠,
because a literal rule compares the description exactly, spaces included.

A pattern that is not a valid regular expression is refused when you save it, rather than failing part-way
through your next import. So is an empty description: ticked as a pattern it would match every
transaction and quietly categorise everything nothing else caught, and left as plain text it could never
match at all.

Most rules are created for you in bulk by [Teaching it your categories](#teaching-it-your-categories).
This screen is for correcting those and adding the ones it could not work out.

#### Making a rule out of a transaction

Noticing that something is filed wrongly happens on the account screen, not here, so you can start a rule
from the row itself. The third icon in a transaction's row opens this form with the **Description** already
filled in from that transaction, exactly as the statement writes it, along with its category and
counterparty if it has them. Hovering over the icon shows the description it would use, which is also the
one place a stray leading or trailing space is visible before you save.

Three fields are deliberately left alone rather than copied from the transaction. **Transaction type** and
**Amount** stay blank, so the rule matches any type and any amount — the same payee can arrive as a `DD` one
month and a `DEB` the next, and most rules are not meant to care what the amount was. And **Treat as a
pattern** stays unticked, an exact description being the more specific claim.

You still see the form before anything is saved, because a rule is a generalisation: it will claim rows you
are not looking at, and it will reach backwards.

#### Saving a rule categorises what you have already imported

A new rule used to affect only the next statement you loaded, which was the wrong way round — you write a
rule *because* something already imported went uncategorised. Now saving one also applies it to the
transactions already in the database, and the message says how many it caught:

```
Rule was successfully created. It also categorised 4 transactions already imported.
```

It only takes rows that **no rule has claimed and nobody has categorised**. A category you chose yourself
is never overwritten, and neither is one another rule won — your judgement always wins, exactly as it does
when you [apply a hand analysis](#correcting-categories). So the **Matched** count above can read one lower
than the number of transactions sharing the description: the row you categorised by hand before writing the
rule keeps your category and is left out.

Editing a rule does the same thing, which is what makes fixing a typo in a description worth doing. Note
that it only ever *adds*: narrowing a rule, or deleting one, does not release the transactions it has
already claimed.

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
wrong, the very first import stops with an error rather than loading thousands of subtly wrong rows — and
nothing is saved, so you can correct the balance and import the same file again.

The easiest way to get it right is to work backwards from the statement you are about to load: take the
oldest transaction in the file, and subtract its amount from the balance shown against it. If the file
is newest-first, the oldest transaction is the **last line**.

4. Now go to **Input Columns Definition** and create one for the account, using the sample-CSV panel
   described above.

The account is now ready to accept statements: open it and press **Import Statement**. Until it has a
column layout that button explains what is missing and offers the link to create one, rather than
refusing to work without saying why.

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

Download the statement from your bank as a CSV, then open the account and press **Import Statement**.
Choose the file, press **Import**, and you are returned to the account with a line saying what happened:

```
Imported 43 transactions into Joint, 1-Aug-24 to 14-Sep-24.  31 categorised by rule, 12 left uncategorised.
```

Transactions matching one of your rules are filed as they load; the rest arrive uncategorised for you to
deal with on the account screen. Check the list afterwards — the balance against the newest transaction
should be the closing balance on your real statement.

**Loading a file twice is safe.** The application recognises the rows it already has and skips them, so
you do not have to remember exactly where you got to. Downloading the last couple of months and importing
the lot is a perfectly good way to catch up:

```
Imported 12 transactions into Joint, 1-Sep-24 to 14-Sep-24, and skipped 31 rows already loaded.
9 categorised by rule, 3 left uncategorised.
```

And if the whole file is one you have already loaded, it says so and does nothing:

```
All 43 rows in that file are already loaded in Joint, so nothing was imported.
```

**If anything does not add up, nothing at all is imported.** The application recalculates the running
balance for every row and checks it against the balance in your statement. Where they disagree it stops,
tells you which row and what the two figures were, and leaves the account exactly as it was — you will
never be left with a half-loaded account to tidy up:

```
Nothing was imported.  Line 2627: 2-Jan-24 EOE COOP FOOD £-1.80 — the statement says the balance is
£3,644.73, where the account works out £998.19.  Check the account's opening balance, and whether this
file covers a period already loaded.
```

The usual causes are an opening balance that is wrong (see [Setting up a new
account](#setting-up-a-new-account)) or a gap — a period between what you have already loaded and the file
you are importing now, which you have not downloaded. Load the missing period first.

A statement of a few thousand rows takes about five seconds; an ordinary month is quicker than you can
notice.

---

## Correcting categories

The rules work on the transaction description, so they treat every `NON-GBP TRANS FEE` the same way. In
practice one might be a holiday and the next a work trip, and only you know which.

Three ways to fix this.

**One at a time, on the account screen.** Change the dropdown in the transaction's row and press the
save button that appears at the end of it.

**By writing a rule for it.** Where a whole payee is filed wrongly, or not filed at all, make a rule from
one of its rows and let it catch the rest — see
[Saving a rule categorises what you have already imported](#saving-a-rule-categorises-what-you-have-already-imported).

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

Your hand judgement always wins over a rule, and re-running changes nothing. That is the same rule a
newly saved import rule follows: it steps over anything you categorised yourself.

---

## Forecasting a month

Once your spending is categorised, the application will tell you what the month is likely to cost and
how much of that has already gone out. It is worth ten minutes' setting up, because the quality of the
answer depends entirely on telling it how each category behaves.

### Telling it how a category behaves

Open **Categories**, edit each one, and choose under **Predict this by**. There are four answers.

**An average of recent months.** The right choice for most categories: Food, Car, Dine Out — the ones
that are steady enough over a month even though no single transaction is predictable. It averages the
last six complete months, ignoring the month you are looking at, and you can change six to anything from
one to twenty-four where that suits the category better.

**Its regular payments, one at a time.** For categories made up of standing bills — Utilities,
Subscriptions. Rather than averaging the category, it recognises each direct debit from your history and
predicts them separately: what each one costs, how often it comes, and whether it has been paid yet this
month. This is much the better answer where it applies, and it needs nothing typed in — though where it
reads your history wrongly, you can put it right. See
[Correcting what it found](#correcting-what-it-found).

**A figure I enter myself.** For Holidays, and anything else where the spending is real, large, and
utterly unlike last month. Nothing can be inferred, so the application asks instead. Open the category
from the forecast and type what you expect; leave the field empty and save to withdraw it. Until you
give a figure the line reads **not set**, and the forecast warns you above the table that its total is
that much too small.

**Not forecast.** For paying off a credit card, and for moving money between two of your own accounts.
That is not spending — the spending already happened on the card — and counting it would count the same
money twice. Excluded categories still appear on the screen, so you can see what has been left out, but
they add nothing to the total.

### What to expect from the regular-payments method

- A payment has to have happened **twice** before it can be worked out on its own, because one occurrence
  says nothing about how often it comes. A new direct debit appears on its second one — or sooner, if you
  tell it the frequency.
- It handles monthly, quarterly, half-yearly and yearly bills, and only expects them in the months they
  are actually due.
- It predicts **the most recent amount**, not an average. Direct debits step up, and last month's figure
  is the best guess at next month's.
- That last point makes it the wrong choice for a genuinely variable bill — energy at £120 in summer and
  £300 in winter. Put that category on the average instead.
- A bill you have cancelled drops off on its own once it has been silent for longer than its own cycle.
- A bill can fall **twice inside one calendar month** — billed on the 1st and again on the 29th, say. The
  workings page lists each charge on its own line, so two ordinary payments are not mistaken for a single
  one that has doubled.
- A payee that appears under two counterparties may not be recognised at all, because its history is
  split in two. Both halves are listed, each saying it was only seen once, so you can see what has
  happened; merge the counterparties on the [Counterparties](#counterparties) screen and it reunites,
  keeping any frequency you had set.

Everything it decided is on the category's own screen, including the payees it left out and why, so a
figure you did not expect can always be traced back to a reason.

### Correcting what it found

Edit a category predicted by its regular payments and you get the whole list, with a frequency dropdown
against each payee. Leave it on **Work it out from the history** and nothing changes. The other choices:

- **Monthly, Quarterly, Twice a year, Yearly** — say how often it comes, and it is forecast at that
  frequency whatever the history reads like. This is how you bring in a direct debit that has only been
  paid once, and how you fix an annual premium that falls a fortnight either side of its anniversary and
  so looks irregular.
- **Not a regular payment** — take it out of the forecast altogether. For a bill you have cancelled and
  do not want to wait out, or a coincidence the application has mistaken for a schedule.

Three things are worth knowing about a frequency you set yourself:

- **It does not keep a dead bill alive.** A payment silent for longer than the frequency you gave, plus a
  month's grace, still drops out. Saying how often something came is not saying it is still coming — so
  use **Not a regular payment** for something genuinely cancelled.
- **The amount is still the last payment**, never a figure you type. A payee that has never been paid in
  a month that has finished is not forecast whatever frequency you give it; it comes in the month after
  its first payment.
- **You can always give it back.** Choose **Work it out from the history** and the setting is cleared, as
  though you had never touched it.

The list describes **the last month you have imported transactions for**, the same month the forecast
opens on, so what it says lines up with the forecast's own workings page. If every payee reads *nothing
since…*, that is not the list being broken: it means your last import is further back than those bills'
own cycles, and loading a more recent statement is what brings them back.

### Reading the month

The forecast is one number per category, less what has already been spent. Where a category is predicted
from its regular payments, that subtraction happens **bill by bill**, which matters more than it sounds:
if the energy bill was expected at £218 and came in at £248, it is settled and the water bill still to
come is untouched. Subtracted at the level of the category, that £30 would have quietly eaten into it.

### Uncategorised spending

Anything with no category gets a line of its own at the bottom, forecast the same way as an average. It
is there because leaving it out would make the total roughly a third too small on real data, with nothing
on the screen to say so. If it is a large number, that is the nudge to write a few more import rules.

Refunds are not counted — the forecast looks at money going out only — so a category with a lot of
returns reads a little high.

---

## Command reference

Run these from the project directory.

| Command | What it does |
| --- | --- |
| `bin/rails server` | Start the application on <http://localhost:3000> |
| `bin/rails db:seed` | Build an account and its full history from the statement files in `db/` — account, rules, transactions and hand categories, in one step. Safe to re-run. |
| `bin/rails "import:analysis[file.csv,Account]"` | Learn categories and rules from a hand-categorised statement |
| `bin/rails "import:categorise[file.csv,Account]"` | Apply hand-assigned categories to transactions already loaded |
| `bin/rails users:create` | Make a login. Asks for the address and password rather than taking them on the command line, so they do not end up in your shell history |
| `bin/rails users:list` | Who has a login, whether two-factor is on, and since when |
| `bin/rails "users:change_password[you@example.com]"` | **A forgotten password.** |
| `bin/rails "users:disable_totp[you@example.com]"` | **A lost phone.** Turns two-factor off so a password alone gets you in; set the app up again afterwards |
| `bin/rails console` | An interactive prompt, for anything the screens do not cover |
| `bundle exec rspec` | Run the test suite (needs Chrome) |
| `bin/rubocop` | Check code style |
| `bin/kamal setup` | Put it on a server for the first time — see [Putting it on a server](#putting-it-on-a-server) |
| `bin/kamal deploy` | Send your latest changes to that server |
| `bin/kamal logs` | Watch what the server is doing |
| `bin/kamal console` | The interactive prompt above, but on the server |

`db:seed` is the quickest route from an empty database to a working one, but it needs the statement
filenames and account name configured in the encrypted credentials. If you are setting up by hand
instead, follow the steps above in order.

---

## When something goes wrong

**"Your Ruby version is 4.0.0, but your Gemfile specified 4.0.6"**
Your shell is on the wrong Ruby. Run `rvm use ruby-4.0.6`. If it keeps happening in new terminals,
something long-running — your editor, or the desktop session — is passing an old environment down to
them; restarting it, or logging out and back in, fixes it.

**The sign-in screen will not accept anything, on a brand-new database**
Nobody has a login yet. Run `bin/rails users:create`. A fresh database has no users in it and there is no
sign-up page, so this is expected rather than broken — `bin/rails db:prepare` says so when it happens.

**I have lost my phone and it is asking for a code**
`bin/rails "users:disable_totp[you@example.com]"`, run on the machine this is installed on — or, if it is
on a server, `bin/kamal app exec --interactive --reuse 'bin/rails "users:disable_totp[you@example.com]"'`
from a machine set up to deploy it. Two-factor goes off, your password alone gets you in, and you can set
a new phone up from your own page afterwards. There are deliberately no backup codes; the reasoning was
that anyone running this has access to the machine it is on, which was a better argument when that machine
was in the house than it is now that it is rented.

**I have forgotten my password**
`bin/rails "users:change_password[you@example.com]"`. There is no reset-by-email: nothing here is set up
to send mail, and a *Forgot your password?* link that quietly did nothing would be worse than not having
one.

**The transaction list stopped loading more rows**
If you were signed out somewhere else while the page sat open, the list will send you back to the sign-in
screen the next time it reaches for more. Sign in again and carry on.

**The import says the statement does not reconcile**
The running balance it works out does not match the one printed in your statement, and the message names
the row and both figures. Almost always the account's opening balance is wrong — see [Setting up a new
account](#setting-up-a-new-account). The other cause is a gap: a period between what you have already
loaded and this file, which was never downloaded. Load the missing period first. Nothing is saved when
this happens, so correct whichever it was and import the same file again.

**The import says the file does not look like a statement for this account**
None of the columns the account's layout expects are in the file. Either it is a download from a different
account, or it has no header row — its first line is a transaction rather than column names — while the
layout says it has one. Untick **Header** on the layout, or choose the file you meant.

**The import says the file has no such-and-such column**
The column layout for that account expects a column your file does not have — usually because the bank
has changed what it exports, or because the file came from a different account. The message lists the
columns your file actually has. Edit the layout under **Input Columns Definition**, or choose the file
you meant.

**The balances on a credit card look wrong**
Card statements from some providers carry no running balance, so the application works it out rather than
checking it. That means it cannot tell when a month is missing: if you import September and November but
never October, every balance from November on is out by whatever October cost, and nothing will say so.
Import the missing month and delete the affected rows, or check the card's own statement for the true
figure. Accounts whose statements do carry a balance — a Lloyds current account, for instance — are
checked on every row and cannot drift this way.

**Transactions imported but none are categorised**
Either no rules exist yet — run the analysis step — or the rules belong to a different account. Rules
are per-account, so a rule learned on your current account will not categorise card transactions.

**A rule I wrote never categorises anything**
Check its **Matched** count on the rules list. If it is zero, the usual causes are a description with
leading or trailing spaces — a literal rule matches exactly, and the list marks those with ⚠ — or a
**Transaction type** that does not match the statement's. Leave the type blank unless you mean it.

**A rule's Matched count is lower than the number of transactions I can see**
Any of those rows that you had already categorised yourself is left alone and not claimed, so it does not
count towards the rule. That is deliberate: your judgement wins. The same is true of a row some other rule
got to first.

**A category's forecast looks far too low**
Open its workings from the forecast. If the months it is averaged over are mostly zeroes, the category
is younger than the six months it looks back over — it is being averaged against months it did not
exist for. Shorten **Months to average over** on the category, or predict that one by hand.

**A direct debit I pay every month is not in the regular payments list**
Edit the category and look at the list there: every payee it found is on it, and the ones left out say
why. Usually it is one of two things. It needs to have happened **twice** before a frequency can be
worked out, so a new one does not appear until its second payment — set the frequency yourself and it
appears now. Or its history is split across two counterparties, in which case neither half has enough
occurrences; merge them on the Counterparties screen.

**The forecast total looks too small**
Check the line above the table. A category set to *A figure I enter myself* contributes nothing until you
give it one, and the screen names the ones still waiting.

**`db:seed` says it is not seeding anything**
It cannot find the statement files in `db/`, or the credentials naming them are not set. It reports
which file is missing.

---

## What isn't built yet

Being honest about the gaps, in the order they matter:

1. **No look at the past.** The forecast tells you about the month ahead, but there is nothing that
   shows a year of Food side by side, no charts, and no comparison of one period against another. The
   only backward view is stepping the forecast back a month at a time to see how it did.
2. **An import cannot be undone.** If you load the right file into the wrong account, or simply the wrong
   file, you have to delete the transactions by hand. A file that *fails* is safe — nothing is saved —
   but one that succeeds is not reversible.
3. **Nothing notices a missing month on an account whose statements carry no balance.** See the note in
   [When something goes wrong](#when-something-goes-wrong). Accounts with a balance column are checked
   row by row and cannot drift.
4. **Nothing warns that a category is too young to average.** A category you created last month and never
   applied to older transactions is averaged over five months of zeroes, so it reads low. The workings
   page shows the zeroes, but you have to go and look.
5. **No way to reset your own password, and no backup codes.** Both are deliberate — see
   [Signing in](#signing-in) — and both mean that being locked out needs someone with access to the
   machine. If this ever runs somewhere you do not own, that is the thing to change first.
6. **Nothing signs you out after a while.** Once you are in, you stay in until you sign out or change
   your password. There is no idle timeout, and no list of where your account has been used from.
7. **A rule only ever claims more, never fewer.** Narrowing a rule, or deleting it, leaves the transactions
   it already categorised exactly as they are. Nor is there any preview: you cannot see how many existing
   transactions a rule would catch until you save it. The same applies across a description shared between
   an amount-specific rule and its default: write the amount-specific one first, or the default will already
   have claimed the rows it should have caught.

How well the automatic categorisation does depends on how much hand analysis you feed it. Against a
year of real statements with one quarter analysed by hand, roughly two thirds of transactions were
categorised automatically, rising to about 85% within the analysed period.
