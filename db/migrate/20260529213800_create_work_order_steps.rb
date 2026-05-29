class CreateWorkOrderSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :work_order_steps, id: :uuid do |t|
      t.references :work_order, null: false, foreign_key: true, type: :uuid
      t.references :bom_item, null: false, foreign_key: true, type: :uuid
      t.string :status, null: false, default: "PENDING"
      t.references :installed_part_instance, type: :uuid, foreign_key: { to_table: :part_instances }
      t.string :installed_actor
      t.datetime :installed_at
      t.string :validated_actor
      t.datetime :validated_at
      t.string :certified_actor
      t.datetime :certified_at

      t.timestamps
    end

    add_check_constraint :work_order_steps, "status in ('PENDING', 'INSTALLED', 'VALIDATED', 'CERTIFIED', 'BLOCKED')", name: "work_order_steps_status_check"
    add_check_constraint :work_order_steps, "validated_actor IS NULL OR validated_actor <> installed_actor", name: "work_order_steps_four_eyes"
  end
end
