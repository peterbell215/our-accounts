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

ActiveRecord::Schema[8.0].define(version: 2025_02_16_045452) do
  create_table "accounts", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "account_number"
    t.string "sortcode"
    t.date "opening_date"
    t.integer "opening_balance_pence", default: 0, null: false
    t.string "opening_balance_currency", default: "GBP", null: false
    t.string "type"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "import_columns_definitions", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "date_column", null: false
    t.string "date_format", null: false
    t.integer "transaction_type_column"
    t.integer "sortcode_column"
    t.integer "account_number_column"
    t.integer "other_party_column"
    t.integer "amount_column"
    t.integer "debit_column"
    t.integer "credit_column"
    t.integer "balance_column"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "credit_sign", default: 1
    t.index ["account_id"], name: "index_import_columns_definitions_on_account_id"
  end

  create_table "import_matchers", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "category_id", null: false
    t.string "description", null: false
    t.boolean "description_is_regex", default: false, null: false
    t.string "trx_type"
    t.integer "other_party_id", null: false
    t.index ["account_id"], name: "index_import_matchers_on_account_id"
    t.index ["category_id"], name: "index_import_matchers_on_category_id"
    t.index ["other_party_id"], name: "index_import_matchers_on_other_party_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "account_id"
    t.integer "category_id"
    t.date "date", null: false
    t.integer "amount_pence", default: 0, null: false
    t.string "amount_currency", default: "GBP", null: false
    t.integer "balance_pence", default: 0, null: false
    t.string "balance_currency", default: "GBP", null: false
    t.integer "day_index"
    t.integer "other_party_id"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["other_party_id"], name: "index_transactions_on_other_party_id"
  end

  add_foreign_key "import_matchers", "accounts"
  add_foreign_key "import_matchers", "accounts", column: "other_party_id"
  add_foreign_key "import_matchers", "categories"
  add_foreign_key "transactions", "accounts", column: "other_party_id"
end
