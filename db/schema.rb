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

ActiveRecord::Schema[8.1].define(version: 2026_08_27_165143) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "api_credentials", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.bigint "merchant_id", null: false
    t.datetime "revoked_at"
    t.string "secret_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_api_credentials_on_key", unique: true
    t.index ["merchant_id", "active"], name: "index_api_credentials_on_merchant_id_and_active"
    t.index ["merchant_id", "revoked_at"], name: "index_api_credentials_on_merchant_id_and_revoked_at"
    t.index ["merchant_id"], name: "index_api_credentials_on_merchant_id"
  end

  create_table "merchants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_merchants_on_name", unique: true
    t.check_constraint "status = ANY (ARRAY[0, 1, 2])", name: "merchants_status_check"
  end

  create_table "order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.bigint "order_id", null: false
    t.string "product_name", null: false
    t.integer "quantity", default: 1, null: false
    t.integer "total_price_cents", null: false
    t.integer "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_name"], name: "index_order_items_on_product_name"
    t.check_constraint "currency::text = ANY (ARRAY['USD'::character varying, 'EUR'::character varying, 'GBP'::character varying, 'JPY'::character varying, 'CAD'::character varying, 'AUD'::character varying, 'CHF'::character varying, 'CNY'::character varying, 'HKD'::character varying, 'NZD'::character varying, 'SEK'::character varying, 'KRW'::character varying, 'SGD'::character varying, 'NOK'::character varying, 'MXN'::character varying, 'INR'::character varying, 'BRL'::character varying, 'ZAR'::character varying, 'TRY'::character varying, 'RUB'::character varying]::text[])", name: "order_items_currency_valid_check"
    t.check_constraint "quantity > 0", name: "order_items_quantity_positive_check"
    t.check_constraint "total_price_cents = (quantity * unit_price_cents)", name: "order_items_total_price_calculation_check"
    t.check_constraint "total_price_cents > 0", name: "order_items_total_price_positive_check"
    t.check_constraint "unit_price_cents > 0", name: "order_items_unit_price_positive_check"
  end

  create_table "orders", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.string "external_reference"
    t.bigint "merchant_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_orders_on_pending_created_at", where: "(status = 0)"
    t.index ["external_reference"], name: "index_orders_on_external_reference", unique: true
    t.index ["merchant_id", "created_at"], name: "index_orders_on_merchant_completed", where: "(status = 1)"
    t.index ["merchant_id", "created_at"], name: "index_orders_on_merchant_id_and_created_at"
    t.index ["merchant_id", "external_reference"], name: "index_orders_on_merchant_id_and_external_reference"
    t.index ["merchant_id", "status"], name: "index_orders_on_merchant_id_and_status"
    t.index ["merchant_id"], name: "index_orders_on_merchant_id"
    t.index ["status"], name: "index_orders_on_status"
    t.check_constraint "amount_cents > 0", name: "orders_amount_positive_check"
    t.check_constraint "currency::text = ANY (ARRAY['USD'::character varying, 'EUR'::character varying, 'GBP'::character varying, 'JPY'::character varying, 'CAD'::character varying, 'AUD'::character varying, 'CHF'::character varying, 'CNY'::character varying, 'HKD'::character varying, 'NZD'::character varying, 'SEK'::character varying, 'KRW'::character varying, 'SGD'::character varying, 'NOK'::character varying, 'MXN'::character varying, 'INR'::character varying, 'BRL'::character varying, 'ZAR'::character varying, 'TRY'::character varying, 'RUB'::character varying]::text[])", name: "orders_currency_valid_check"
    t.check_constraint "external_reference IS NULL OR length(TRIM(BOTH FROM external_reference)) > 0", name: "orders_external_reference_not_empty_check"
    t.check_constraint "status = ANY (ARRAY[0, 1, 2, 3, 4, 5])", name: "orders_status_valid_check"
  end

  create_table "payments", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.string "billing_address"
    t.string "card_brand"
    t.string "card_last_four"
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.string "failure_reason"
    t.string "idempotency_key"
    t.bigint "merchant_id", null: false
    t.bigint "order_id", null: false
    t.string "payment_method"
    t.string "provider_reference"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_payments_on_pending_created_at", where: "(status = 0)"
    t.index ["idempotency_key"], name: "index_payments_on_idempotency_key", where: "(idempotency_key IS NOT NULL)"
    t.index ["merchant_id", "created_at", "status"], name: "index_payments_on_merchant_id_and_created_at_and_status"
    t.index ["merchant_id", "created_at"], name: "index_payments_on_merchant_completed", where: "(status = 1)"
    t.index ["merchant_id", "currency", "status"], name: "index_payments_on_merchant_id_and_currency_and_status"
    t.index ["merchant_id", "status"], name: "index_payments_on_merchant_id_and_status"
    t.index ["merchant_id"], name: "index_payments_on_merchant_id"
    t.index ["order_id", "idempotency_key"], name: "index_payments_on_order_id_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["order_id", "status"], name: "index_payments_on_order_id_and_status"
    t.index ["order_id"], name: "index_payments_on_order_id"
    t.index ["payment_method"], name: "index_payments_on_payment_method"
    t.index ["provider_reference"], name: "index_payments_on_provider_reference", unique: true
    t.index ["status"], name: "index_payments_on_status"
    t.check_constraint "amount_cents > 0", name: "payments_amount_positive_check"
    t.check_constraint "currency::text = ANY (ARRAY['USD'::character varying, 'EUR'::character varying, 'GBP'::character varying, 'JPY'::character varying, 'CAD'::character varying, 'AUD'::character varying, 'CHF'::character varying, 'CNY'::character varying, 'HKD'::character varying, 'NZD'::character varying, 'SEK'::character varying, 'KRW'::character varying, 'SGD'::character varying, 'NOK'::character varying, 'MXN'::character varying, 'INR'::character varying, 'BRL'::character varying, 'ZAR'::character varying, 'TRY'::character varying, 'RUB'::character varying]::text[])", name: "payments_currency_valid_check"
    t.check_constraint "status = 1 AND provider_reference IS NOT NULL OR status <> 1", name: "payments_provider_reference_check"
    t.check_constraint "status = 3 AND failure_reason IS NOT NULL OR status <> 3 AND failure_reason IS NULL", name: "payments_failure_reason_check"
    t.check_constraint "status = ANY (ARRAY[0, 1, 2, 3, 4])", name: "payments_status_valid_check"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "first_name"
    t.datetime "last_activity_at"
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "locked_at"
    t.bigint "merchant_id", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role", default: "user", null: false
    t.integer "sign_in_count", default: 0, null: false
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_users_on_active"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["merchant_id", "active"], name: "index_users_on_merchant_id_and_active"
    t.index ["merchant_id", "role"], name: "index_users_on_merchant_id_and_role"
    t.index ["merchant_id"], name: "index_users_on_merchant_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
    t.check_constraint "role::text = ANY (ARRAY['user'::character varying, 'admin'::character varying, 'super_admin'::character varying]::text[])", name: "users_role_check"
  end

  add_foreign_key "api_credentials", "merchants"
  add_foreign_key "order_items", "orders"
  add_foreign_key "orders", "merchants"
  add_foreign_key "payments", "merchants"
  add_foreign_key "payments", "orders"
  add_foreign_key "users", "merchants"
end
