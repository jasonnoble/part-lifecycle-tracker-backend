class CreateSupplierPurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :supplier_purchase_orders, id: :uuid do |t|
      t.string :supplier_id, null: false
      t.string :status, null: false, default: "OPEN"
      t.references :customer_order, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_check_constraint :supplier_purchase_orders, "status in ('OPEN', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CLOSED')", name: "supplier_purchase_orders_status_check"
    add_check_constraint :supplier_purchase_orders, "length(trim(supplier_id)) > 0", name: "supplier_purchase_orders_supplier_id_present"
  end
end
