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

ActiveRecord::Schema[8.1].define(version: 2026_05_29_165556) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "bom_item_dependencies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.uuid "dependent_bom_item_id", null: false
    t.uuid "prerequisite_bom_item_id", null: false
    t.index ["dependent_bom_item_id"], name: "index_bom_item_dependencies_on_dependent_bom_item_id"
    t.index ["prerequisite_bom_item_id", "dependent_bom_item_id"], name: "index_bom_item_deps_on_prereq_and_dependent", unique: true
    t.index ["prerequisite_bom_item_id"], name: "index_bom_item_dependencies_on_prerequisite_bom_item_id"
    t.check_constraint "prerequisite_bom_item_id <> dependent_bom_item_id", name: "bom_item_dependencies_no_self_reference"
  end

  create_table "bom_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "child_part_definition_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.uuid "parent_part_definition_id", null: false
    t.integer "quantity", null: false
    t.datetime "updated_at", null: false
    t.index ["child_part_definition_id"], name: "index_bom_items_on_child_part_definition_id"
    t.index ["parent_part_definition_id", "child_part_definition_id"], name: "index_bom_items_on_parent_child_active", unique: true, where: "(deleted_at IS NULL)"
    t.index ["parent_part_definition_id"], name: "index_bom_items_on_parent_part_definition_id"
    t.check_constraint "parent_part_definition_id <> child_part_definition_id", name: "bom_items_no_self_reference"
    t.check_constraint "quantity > 0", name: "bom_items_quantity_positive"
  end

  create_table "part_definitions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "part_number", null: false
    t.string "revision"
    t.string "status", default: "DRAFT", null: false
    t.datetime "updated_at", null: false
    t.index ["part_number"], name: "index_part_definitions_on_part_number", unique: true
    t.check_constraint "length(TRIM(BOTH FROM name)) > 0", name: "part_definitions_name_present"
    t.check_constraint "length(TRIM(BOTH FROM part_number)) > 0", name: "part_definitions_part_number_present"
    t.check_constraint "status::text = ANY (ARRAY['DRAFT'::character varying::text, 'RELEASED'::character varying::text, 'OBSOLETE'::character varying::text])", name: "part_definitions_status_check"
  end

  add_foreign_key "bom_item_dependencies", "bom_items", column: "dependent_bom_item_id"
  add_foreign_key "bom_item_dependencies", "bom_items", column: "prerequisite_bom_item_id"
  add_foreign_key "bom_items", "part_definitions", column: "child_part_definition_id"
  add_foreign_key "bom_items", "part_definitions", column: "parent_part_definition_id"
end
