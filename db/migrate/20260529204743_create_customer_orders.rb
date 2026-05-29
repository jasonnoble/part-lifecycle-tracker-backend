class CreateCustomerOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :customer_orders, id: :uuid do |t|
      t.string :customer_name, null: false
      t.string :status, null: false, default: 'OPEN'

      t.timestamps
    end

    add_check_constraint :customer_orders, "status in ('OPEN', 'IN_FULFILLMENT', 'COMPLETE')", name: "customer_orders_status_check"
    add_check_constraint :customer_orders, "length(trim(customer_name)) > 0", name: "customer_orders_customer_name_present"
  end
end
