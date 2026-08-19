# TODO

Known problems and work worth picking up, with enough context to start on them cold. Larger themes —
the missing import UI, the absent analysis features — are recorded under **Where it stands** in
`design_docs/architecture.md` and **What isn't built yet** in `README.md` rather than here.

---

## An index on `transactions (account_id, date)`

`Transaction#sequence` runs `account.transactions.where("date <= ?", date).order(:date, :day_index).last`
once for **every row being imported**, and `transactions` has an index on `account_id` alone and none on
`date`. So importing a 2,626-row statement scans a growing table 2,626 times, and the cost grows with the
square of the file. `Transaction.on_or_before` runs the same shape of query on every scroll of the
transaction list.

The fix is one line — `add_index :transactions, [ :account_id, :date ]` — in its own migration, with a
comment naming `#sequence` as the reason. The existing single-column `account_id` index becomes redundant
against it; dropping that is a separate argument and need not hold this up.

Noticed while building the forecast, which does not itself need this index: its own queries filter on
date across all categories, or on `category_id` across all history, and the second is already served.

---

The one entry this file previously held — a row scrolled out of the rendered window and back appearing to lose an
unsaved category — is fixed. The category was never lost: the buffer held the edited row throughout, and
what failed was scrolling back to it, because the window could only ever slide forward. The reasoning is
in `design_docs/architecture.md` under "The box is only just taller than the rows in it".
