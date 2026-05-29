class CreatePartDefinitions < ActiveRecord::Migration[8.1]
  def change
    create_table :part_definitions, id: :uuid do |t|
      t.string :part_number, null: false
      t.string :name, null: false
      t.text :description
      t.string :revision
      t.string :status, null: false, default: 'DRAFT'

      t.timestamps
    end

    add_index :part_definitions, :part_number, unique: true
    add_check_constraint :part_definitions, "status in ('DRAFT','RELEASED','OBSOLETE')",
                         name: "part_definitions_status_check"
    add_check_constraint :part_definitions, "length(trim(part_number)) > 0",
                         name: "part_definitions_part_number_present"
    add_check_constraint :part_definitions, "length(trim(name)) > 0",
                         name: "part_definitions_name_present"
  end
end
