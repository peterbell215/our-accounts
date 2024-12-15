# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2024_12_15_164411) do
  create_table "accounts", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "account_number"
    t.string "sortcode"
    t.date "opening_date"
    t.integer "opening_balance_pence", default: 0, null: false
    t.string "opening_balance_currency", default: "GBP", null: false
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "transactions", force: :cascade do |t|
    t.date "date"
    t.integer "amount_pence", default: 0, null: false
    t.string "amount_currency", default: "GBP", null: false
    t.integer "creditor_id", null: false
    t.integer "debitor_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "category_id"
    t.integer "previous_trx_id", null: false
    t.integer "balance_pence", default: 0, null: false
    t.string "balance_currency", default: "GBP", null: false
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["creditor_id"], name: "index_transactions_on_creditor_id"
    t.index ["debitor_id"], name: "index_transactions_on_debitor_id"
    t.index ["previous_trx_id"], name: "index_transactions_on_previous_trx_id"
  end

  add_foreign_key "transactions", "accounts", column: "creditor_id"
  add_foreign_key "transactions", "accounts", column: "debitor_id"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "transactions", column: "previous_trx_id"
end
