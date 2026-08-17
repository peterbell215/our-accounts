# TODO

Known problems and work worth picking up, with enough context to start on them cold. Larger themes —
the missing import UI, the absent analysis features — are recorded under **Where it stands** in
`design_docs/architecture.md` and **What isn't built yet** in `README.md` rather than here.

---

Nothing outstanding.

The one entry this file held — a row scrolled out of the rendered window and back appearing to lose an
unsaved category — is fixed. The category was never lost: the buffer held the edited row throughout, and
what failed was scrolling back to it, because the window could only ever slide forward. The reasoning is
in `design_docs/architecture.md` under "The box is only just taller than the rows in it".
