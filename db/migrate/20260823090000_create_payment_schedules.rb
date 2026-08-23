class CreatePaymentSchedules < ActiveRecord::Migration[8.1]
  def change
    # A frequency the user has set by hand for one payee in one category, overriding what
    # Forecast::RegularPayments would have inferred from the history.
    #
    # A row exists only where the user has ruled on a payee — no row means "work it out" — and its
    # identity mirrors the grouping key the detector uses at runtime, `counterparty_id || description`.
    # Plenty of direct debits never acquired a counterparty, so the description has to serve as the
    # payee for those, exactly as it does in the detector.
    create_table :payment_schedules do |t|
      t.references :category, null: false, foreign_key: true, index: false
      # `index: false` above: both composite indexes below lead on category_id and cover it.
      t.references :counterparty, foreign_key: { to_table: :accounts }, index: false
      t.string :description
      # 1, 3, 6 or 12.  Null on a row that exists means "not a regular payment" — see PaymentSchedule.
      t.integer :cadence_months

      t.timestamps
    end

    # One ruling per payee per category, whichever way the payee is identified.
    #
    # Two partial indexes rather than one over all three columns, because SQLite treats NULLs as
    # distinct: a single unique index on (category_id, counterparty_id, description) would let the same
    # counterparty be ruled on twice, both rows having a null description.
    add_index :payment_schedules, [ :category_id, :counterparty_id ], unique: true,
              where: "counterparty_id IS NOT NULL",
              name: "index_payment_schedules_on_category_and_counterparty"
    add_index :payment_schedules, [ :category_id, :description ], unique: true,
              where: "description IS NOT NULL",
              name: "index_payment_schedules_on_category_and_description"
  end
end
