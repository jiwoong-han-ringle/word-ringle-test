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

ActiveRecord::Schema[8.0].define(version: 2025_09_05_021632) do
  create_table "relation_words", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "word_id", null: false
    t.string "word_text", limit: 50, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["word_id"], name: "index_relation_words_on_word_id"
    t.index ["word_text"], name: "index_relation_words_on_word_text", unique: true
  end

  create_table "user_counts", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.date "date", null: false
    t.integer "total_words", default: 0
    t.integer "unique_words", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "date"], name: "index_user_counts_on_user_id_and_date", unique: true
  end

  create_table "words", primary_key: "word_id", charset: "utf8mb4", force: :cascade do |t|
    t.string "lemma", limit: 50, null: false
    t.string "word_type", null: false
    t.timestamp "created_at", default: -> { "CURRENT_TIMESTAMP" }
    t.index ["lemma"], name: "index_words_on_lemma", unique: true
  end

  create_table "words_used", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.json "history"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_words_used_on_user_id"
  end

  add_foreign_key "relation_words", "words", primary_key: "word_id"
end
