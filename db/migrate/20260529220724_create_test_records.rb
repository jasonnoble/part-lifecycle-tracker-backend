class CreateTestRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :test_records, id: :uuid do |t|
      t.references :part_instance, null: false, foreign_key: true, type: :uuid
      t.string :test_type, null: false
      t.string :result, null: false
      t.text :notes
      t.string :conducted_by, null: false
      t.datetime :occurred_at, null: false
      t.datetime :recorded_at, null: false, default: -> { "now()" }
    end

    add_check_constraint :test_records, "result in ('PASS', 'FAIL', 'INCONCLUSIVE')", name: "test_records_result_check"
    add_check_constraint :test_records, "length(trim(conducted_by)) > 0", name: "test_records_conducted_by_present"
    add_check_constraint :test_records, "length(trim(test_type)) > 0", name: "test_records_test_type_present"
  end
end
