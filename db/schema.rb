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

ActiveRecord::Schema[7.1].define(version: 2025_09_11_081543) do
  create_table "destinations", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "prefecture_group_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_destinations_on_name", unique: true
    t.index ["prefecture_group_id"], name: "index_destinations_on_prefecture_group_id"
  end

  create_table "plan_destinations", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "travel_plan_id", null: false
    t.bigint "destination_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["destination_id"], name: "index_plan_destinations_on_destination_id"
    t.index ["travel_plan_id"], name: "index_plan_destinations_on_travel_plan_id"
  end

  create_table "prefecture_groups", charset: "utf8mb3", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "travel_plans", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.integer "budget"
    t.text "notes"
    t.string "status", default: "draft"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "itinerary"
    t.bigint "travel_purpose_id"
    t.index ["travel_purpose_id"], name: "index_travel_plans_on_travel_purpose_id"
    t.index ["user_id"], name: "index_travel_plans_on_user_id"
  end

  create_table "travel_purposes", charset: "utf8mb3", force: :cascade do |t|
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_travel_purposes_on_name", unique: true
  end

  create_table "users", charset: "utf8mb3", force: :cascade do |t|
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "nickname", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "home_destination_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["home_destination_id"], name: "index_users_on_home_destination_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "destinations", "prefecture_groups"
  add_foreign_key "plan_destinations", "destinations"
  add_foreign_key "plan_destinations", "travel_plans"
  add_foreign_key "travel_plans", "travel_purposes"
  add_foreign_key "travel_plans", "users"
  add_foreign_key "users", "destinations", column: "home_destination_id", on_delete: :nullify
end
