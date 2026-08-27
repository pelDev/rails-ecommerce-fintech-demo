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

ActiveRecord::Schema[8.1].define(version: 2026_08_27_133946) do
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

  add_foreign_key "api_credentials", "merchants"
end
