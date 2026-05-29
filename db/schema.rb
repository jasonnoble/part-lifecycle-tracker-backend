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

ActiveRecord::Schema[8.1].define(version: 2026_05_29_181529) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "bom_item_dependencies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.uuid "dependent_bom_item_id", null: false
    t.uuid "prerequisite_bom_item_id", null: false
    t.index [ "dependent_bom_item_id" ], name: "index_bom_item_dependencies_on_dependent_bom_item_id"
    t.index [ "prerequisite_bom_item_id", "dependent_bom_item_id" ], name: "index_bom_item_deps_on_prereq_and_dependent", unique: true
    t.index [ "prerequisite_bom_item_id" ], name: "index_bom_item_dependencies_on_prerequisite_bom_item_id"
    t.check_constraint "prerequisite_bom_item_id <> dependent_bom_item_id", name: "bom_item_dependencies_no_self_reference"
  end

  create_table "bom_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "child_part_definition_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.uuid "parent_part_definition_id", null: false
    t.integer "quantity", null: false
    t.datetime "updated_at", null: false
    t.index [ "child_part_definition_id" ], name: "index_bom_items_on_child_part_definition_id"
    t.index [ "parent_part_definition_id", "child_part_definition_id" ], name: "index_bom_items_on_parent_child_active", unique: true, where: "(deleted_at IS NULL)"
    t.index [ "parent_part_definition_id" ], name: "index_bom_items_on_parent_part_definition_id"
    t.check_constraint "parent_part_definition_id <> child_part_definition_id", name: "bom_items_no_self_reference"
    t.check_constraint "quantity > 0", name: "bom_items_quantity_positive"
  end

  create_table "lifecycle_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "actor", null: false
    t.string "event_type", null: false
    t.jsonb "metadata"
    t.text "notes"
    t.datetime "occurred_at", null: false
    t.uuid "part_instance_id", null: false
    t.datetime "recorded_at", default: -> { "now()" }, null: false
    t.index [ "occurred_at" ], name: "index_lifecycle_events_on_occurred_at"
    t.index [ "part_instance_id", "occurred_at" ], name: "index_lifecycle_events_on_instance_occurred_at"
    t.check_constraint "event_type::text = ANY (ARRAY['ORDERED'::character varying, 'RECEIVED'::character varying, 'INSPECTED'::character varying, 'IN_ASSEMBLY'::character varying, 'INSTALLED'::character varying, 'VALIDATED'::character varying, 'CERTIFIED'::character varying]::text[])", name: "lifecycle_events_event_type_check"
    t.check_constraint "length(TRIM(BOTH FROM actor)) > 0", name: "lifecycle_events_actor_present"
  end

  create_table "part_definitions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "part_number", null: false
    t.string "revision"
    t.string "status", default: "DRAFT", null: false
    t.datetime "updated_at", null: false
    t.index [ "part_number" ], name: "index_part_definitions_on_part_number", unique: true
    t.check_constraint "length(TRIM(BOTH FROM name)) > 0", name: "part_definitions_name_present"
    t.check_constraint "length(TRIM(BOTH FROM part_number)) > 0", name: "part_definitions_part_number_present"
    t.check_constraint "status::text = ANY (ARRAY['DRAFT'::character varying, 'RELEASED'::character varying, 'OBSOLETE'::character varying]::text[])", name: "part_definitions_status_check"
  end

  create_table "part_instances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "current_status", null: false
    t.uuid "part_definition_id", null: false
    t.string "serial_number", null: false
    t.datetime "updated_at", null: false
    t.index [ "part_definition_id" ], name: "index_part_instances_on_part_definition_id"
    t.index [ "serial_number" ], name: "index_part_instances_on_serial_number", unique: true
    t.check_constraint "current_status::text = ANY (ARRAY['ORDERED'::character varying, 'RECEIVED'::character varying, 'INSPECTED'::character varying, 'IN_ASSEMBLY'::character varying, 'INSTALLED'::character varying, 'VALIDATED'::character varying, 'CERTIFIED'::character varying]::text[])", name: "part_instances_current_status_check"
    t.check_constraint "length(TRIM(BOTH FROM serial_number)) > 0", name: "part_instances_serial_number_present"
  end

  create_table "stock_audit_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "change_amount", null: false
    t.uuid "part_definition_id", null: false
    t.string "reason", null: false
    t.datetime "recorded_at", default: -> { "now()" }, null: false
    t.index [ "part_definition_id", "recorded_at" ], name: "index_stock_audit_logs_on_part_definition_id_and_recorded_at"
    t.check_constraint "change_amount <> 0", name: "stock_audit_logs_change_amount_non_zero"
    t.check_constraint "length(TRIM(BOTH FROM reason)) > 0", name: "stock_audit_logs_reason_present"
  end

  create_table "stocks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "part_definition_id", null: false
    t.integer "quantity_on_hand", default: 0, null: false
    t.integer "quantity_reserved", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index [ "part_definition_id" ], name: "index_stocks_on_part_definition_id", unique: true
    t.check_constraint "quantity_on_hand >= 0", name: "stock_quantity_on_hand_non_negative"
    t.check_constraint "quantity_reserved >= 0", name: "stock_quantity_reserved_non_negative"
  end

  add_foreign_key "bom_item_dependencies", "bom_items", column: "dependent_bom_item_id"
  add_foreign_key "bom_item_dependencies", "bom_items", column: "prerequisite_bom_item_id"
  add_foreign_key "bom_items", "part_definitions", column: "child_part_definition_id"
  add_foreign_key "bom_items", "part_definitions", column: "parent_part_definition_id"
  add_foreign_key "lifecycle_events", "part_instances"
  add_foreign_key "part_instances", "part_definitions"
  add_foreign_key "stock_audit_logs", "part_definitions"
  add_foreign_key "stocks", "part_definitions"
end
