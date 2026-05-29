class CreateCustomerOrderLines < ActiveRecord::Migration[8.1]
  def change
    create_table :customer_order_lines, id: :uuid do |t|
      t.references :customer_order, null: false, type: :uuid, foreign_key: { to_table: :customer_orders }
      t.references :part_definition, null: false, index: false, type: :uuid, foreign_key: { to_table: :part_definitions }
      t.integer :quantity, null: false

      t.timestamps
    end

    add_check_constraint :customer_order_lines, "quantity > 0", name: "customer_order_lines_quantity_positive"
  end
end
