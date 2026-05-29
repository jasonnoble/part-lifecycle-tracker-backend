class CreateBomItems < ActiveRecord::Migration[8.1]
  def change
    create_table :bom_items, id: :uuid do |t|
      t.references :parent_part_definition, null: false, type: :uuid, foreign_key: { to_table: :part_definitions }
      t.references :child_part_definition, null: false, type: :uuid, foreign_key: { to_table: :part_definitions }
      t.integer :quantity, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :bom_items,
              [ :parent_part_definition_id, :child_part_definition_id ],
              unique: true,
              where: "deleted_at IS NULL",
              name: "index_bom_items_on_parent_child_active"
    add_check_constraint :bom_items, "quantity > 0", name: "bom_items_quantity_positive"
    add_check_constraint :bom_items,
                         "parent_part_definition_id <> child_part_definition_id",
                         name: "bom_items_no_self_reference"
  end
end
