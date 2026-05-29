class CreatePartInstances < ActiveRecord::Migration[8.1]
  def change
    create_table :part_instances, id: :uuid do |t|
      t.string :serial_number, null: false
      t.references :part_definition, null: false, type: :uuid,
        foreign_key: { to_table: :part_definitions }
      t.string :current_status, null: false

      t.timestamps
    end

    add_index :part_instances, :serial_number, unique: true
    add_check_constraint :part_instances, "current_status in ('ORDERED','RECEIVED','INSPECTED', 'IN_ASSEMBLY', 'INSTALLED', 'VALIDATED', 'CERTIFIED')",
                         name: "part_instances_current_status_check"
    add_check_constraint :part_instances, "length(trim(serial_number)) > 0",
                         name: "part_instances_serial_number_present"
  end
end
