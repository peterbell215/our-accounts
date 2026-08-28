# TODO

Known problems and work worth picking up, with enough context to start on them cold. Larger themes —
the absent analysis features — are recorded under **Where it stands** in `design_docs/architecture.md`
and **What isn't built yet** in `README.md` rather than here.

---

## Drop the now-redundant index on `transactions (account_id)`

`index_transactions_on_account_id` is a strict prefix of `index_transactions_on_account_id_and_date`, added
when the import screen was built, so SQLite can answer everything the single-column index served from the
composite one instead. Nothing needs both.

It was left in place because dropping it is a separate argument from adding the composite: the composite
index is wider, so every write to `transactions` maintains a little more, and an import writes a few
thousand rows at a time. Measuring that before removing the cheaper index is the honest order to do it in.

One line — `remove_index :transactions, :account_id` — in its own migration, with a comment naming the
composite index as the reason.

---

## `strip_leading_quote` does nothing for a headerless file

`ImportedTransactionFactory.strip_leading_quote` iterates `csv_row.each do |field, s|`, which destructures
the header/value pairs of a `CSV::Row`. For a definition with `header: false` the row is a plain `Array`,
so the block's second parameter is always `nil` and nothing is ever stripped.

So a Barclaycard-style file that has been through Excel keeps the leading `'` on any field that has one,
and those fields import with the quote still attached. It has not bitten in practice, because the fields
Excel marks that way in the real files are the sort code and account number, which an index-based layout
does not map.

Noticed while building the import screen, which did not cause it and does not depend on it. The fix is to
branch on whether the row responds to `headers`, with a spec for each half.

---

The two entries this file previously held are both closed. A row scrolled out of the rendered window and
back appeared to lose an unsaved category — the category was never lost, and the reasoning is in
`design_docs/architecture.md` under "The box is only just taller than the rows in it". And the missing
index on `transactions (account_id, date)` was added with the import screen, which is what made an import
runnable inside a web request rather than only from `bin/rails runner`.
