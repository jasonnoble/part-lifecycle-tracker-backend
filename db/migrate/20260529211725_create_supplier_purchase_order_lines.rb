class CreateSupplierPurchaseOrderLines < ActiveRecord::Migration[8.1]
  def change
    create_table :supplier_purchase_order_lines, id: :uuid do |t|
      t.references :supplier_purchase_order, null: false, foreign_key: true, type: :uuid
      t.references :part_definition, null: false, foreign_key: true, type: :uuid
      t.integer :quantity, null: false
      t.integer :quantity_received, null: false, default: 0
      t.string :status, null: false, default: "NEEDS_ORDERING"

      t.timestamps
    end

    add_check_constraint :supplier_purchase_order_lines, "status in ('NEEDS_ORDERING', 'ORDERED', 'PARTIALLY_RECEIVED', 'RECEIVED')", name: "supplier_purchase_order_lines_status_check"
    add_check_constraint :supplier_purchase_order_lines, "quantity > 0", name: "supplier_purchase_order_lines_quantity_positive"
    add_check_constraint :supplier_purchase_order_lines, "quantity_received >= 0", name: "supplier_purchase_order_lines_quantity_received_non_negative"
  end
end
