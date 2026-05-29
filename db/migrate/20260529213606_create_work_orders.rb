class CreateWorkOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :work_orders, id: :uuid do |t|
      t.references :part_definition, null: false, foreign_key: true, type: :uuid
      t.references :part_instance, null: false, foreign_key: true, type: :uuid
      t.references :customer_order_line, type: :uuid, foreign_key: { to_table: :customer_order_lines }
      t.string :status, null: false, default: "OPEN"

      t.timestamps
    end

    add_check_constraint :work_orders, "status in ('OPEN', 'BLOCKED', 'COMPLETE')", name: "work_orders_status_check"
  end
end
