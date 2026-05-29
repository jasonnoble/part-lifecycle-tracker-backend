class CreateBomItemDependencies < ActiveRecord::Migration[8.1]
  def change
    create_table :bom_item_dependencies, id: :uuid do |t|
      t.references :prerequisite_bom_item, null: false, type: :uuid,
                   foreign_key: { to_table: :bom_items }
      t.references :dependent_bom_item, null: false, type: :uuid,
                   foreign_key: { to_table: :bom_items }

      t.datetime :created_at, null: false, default: -> { "now()" }
    end

    add_index :bom_item_dependencies,
              [ :prerequisite_bom_item_id, :dependent_bom_item_id ],
              unique: true,
              name: "index_bom_item_deps_on_prereq_and_dependent"

    add_check_constraint :bom_item_dependencies,
                         "prerequisite_bom_item_id <> dependent_bom_item_id",
                         name: "bom_item_dependencies_no_self_reference"
  end
end
