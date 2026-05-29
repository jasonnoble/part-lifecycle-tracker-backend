class CreateStocks < ActiveRecord::Migration[8.1]
  def change
    create_table :stocks, id: :uuid do |t|
      t.references :part_definition, null: false, index: false, type: :uuid, foreign_key: { to_table: :part_definitions }
      t.integer :quantity_on_hand, null: false, default: 0
      t.integer :quantity_reserved, null: false, default: 0

      t.timestamps
    end

    add_index :stocks, :part_definition_id, unique: true
    add_check_constraint :stocks, "quantity_on_hand >= 0", name: "stock_quantity_on_hand_non_negative"
    add_check_constraint :stocks, "quantity_reserved >= 0", name: "stock_quantity_reserved_non_negative"
  end
end
