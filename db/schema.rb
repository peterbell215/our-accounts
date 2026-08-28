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

ActiveRecord::Schema[8.1].define(version: 2026_08_28_100000) do
  create_table "accounts", force: :cascade do |t|
    t.string "account_number"
    t.datetime "created_at", null: false
    t.string "name"
    t.string "opening_balance_currency", default: "GBP", null: false
    t.integer "opening_balance_pence", default: 0, null: false
    t.date "opening_date"
    t.string "sortcode"
    t.string "type"
    t.datetime "updated_at", null: false
  end

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "forecast_method", default: "monthly_average", null: false
    t.integer "forecast_months"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "import_columns_definitions", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "account_number_column"
    t.integer "amount_column"
    t.string "balance_column"
    t.datetime "created_at", null: false
    t.string "credit_column"
    t.integer "credit_sign", default: 1
    t.string "date_column"
    t.string "date_format", null: false
    t.string "debit_column"
    t.boolean "header", default: true
    t.string "other_party_column"
    t.boolean "reversed", default: false
    t.string "sortcode_column"
    t.string "trx_type_column"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_import_columns_definitions_on_account_id"
  end

  create_table "import_matchers", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "category_id", null: false
    t.integer "counterparty_id"
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.boolean "description_is_regex", default: false, null: false
    t.string "trx_type"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_import_matchers_on_account_id"
    t.index ["category_id"], name: "index_import_matchers_on_category_id"
    t.index ["counterparty_id"], name: "index_import_matchers_on_counterparty_id"
  end

  create_table "manual_forecasts", force: :cascade do |t|
    t.string "amount_currency", default: "GBP", null: false
    t.integer "amount_pence", default: 0, null: false
    t.integer "category_id", null: false
    t.datetime "created_at", null: false
    t.date "month", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id", "month"], name: "index_manual_forecasts_on_category_id_and_month", unique: true
  end

  create_table "payment_schedules", force: :cascade do |t|
    t.integer "cadence_months"
    t.integer "category_id", null: false
    t.integer "counterparty_id"
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "updated_at", null: false
    t.index ["category_id", "counterparty_id"], name: "index_payment_schedules_on_category_and_counterparty", unique: true, where: "counterparty_id IS NOT NULL"
    t.index ["category_id", "description"], name: "index_payment_schedules_on_category_and_description", unique: true, where: "description IS NOT NULL"
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "account_id"
    t.string "amount_currency", default: "GBP", null: false
    t.integer "amount_pence", default: 0, null: false
    t.string "balance_currency", default: "GBP", null: false
    t.integer "balance_pence"
    t.integer "category_id"
    t.integer "counterparty_id"
    t.date "date", null: false
    t.integer "day_index"
    t.string "description"
    t.integer "import_matcher_id"
    t.string "trx_type"
    t.index ["account_id", "date"], name: "index_transactions_on_account_id_and_date"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["counterparty_id"], name: "index_transactions_on_counterparty_id"
    t.index ["import_matcher_id"], name: "index_transactions_on_import_matcher_id"
  end

  add_foreign_key "import_matchers", "accounts"
  add_foreign_key "import_matchers", "accounts", column: "counterparty_id"
  add_foreign_key "import_matchers", "categories"
  add_foreign_key "manual_forecasts", "categories"
  add_foreign_key "payment_schedules", "accounts", column: "counterparty_id"
  add_foreign_key "payment_schedules", "categories"
  add_foreign_key "transactions", "accounts", column: "counterparty_id"
end
