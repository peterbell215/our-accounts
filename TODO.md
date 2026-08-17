# TODO

Known problems and work worth picking up, with enough context to start on them cold. Larger themes —
the missing import UI, the absent analysis features — are recorded under **Where it stands** in
`design_docs/architecture.md` and **What isn't built yet** in `README.md` rather than here.

---

## A row scrolled out of the window and back loses an unsaved category

**Status:** open, failing on `main` since 2026-08-17. Roughly one run in two.

`spec/system/transaction_paging_spec.rb:147` — *"rows already fetched keep any category the reader had
chosen but not yet saved"* — fails intermittently, on CI and locally alike:

```
Failure/Error: expect(page.all(".transaction-row").first.find("select").value).to eq(travel.id.to_s)
  expected: "2"
       got: ""
```

The spec picks the newest row, chooses "Travel" in its category dropdown **without saving**, scrolls to
the oldest transaction and back, and expects the dropdown still to read "Travel". It intermittently
comes back empty.

That is precisely the guarantee the design claims: rows leaving the rendered window are **detached
rather than discarded**, so scrolling back re-attaches the same element and any unsaved state in it
survives, because a detached node keeps its own DOM state (`design_docs/architecture.md`, "Rendered rows
are capped, not merely paged"). An empty value means the row came back **freshly rendered rather than
re-attached** — so the likeliest reading is a real bug in the `transactions_list` Stimulus controller,
not merely an over-strict assertion. A reader who scrolled away mid-edit would occasionally lose the
category they had just picked, silently.

Worth ruling out before rewriting anything, in this order:

1. Whether a fetch in flight while the window slides replaces the entries in the controller's row array
   with newly parsed nodes, discarding the detached originals.
2. Whether `scroll_to_newest` can satisfy its poll — "PAYEE 30" is on the page — while the slide it
   triggered is still in progress, so the assertion reads a row that is about to be replaced. If this is
   the whole story the fix is in the spec, but it does not explain an *empty* select on its own.

Reproduce with:

```sh
for i in 1 2 3; do CI=1 bundle exec rspec spec/system/transaction_paging_spec.rb:147; done
```

`CI=1` selects the headless driver; drop it to watch the browser do it.

Do not paper over it by relaxing the assertion until (1) is eliminated — the assertion is testing a
promise the application actually makes to the reader.
