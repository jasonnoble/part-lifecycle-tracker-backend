class CreateStockAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :stock_audit_logs, id: :uuid do |t|
      t.references :part_definition, null: false, type: :uuid, index: false, foreign_key: { to_table: :part_definitions }
      t.integer :change_amount, null: false
      t.string :reason, null: false
      t.datetime :recorded_at, null: false, default: -> { 'now()' }
    end

    add_index :stock_audit_logs, [ :part_definition_id, :recorded_at ], name: :index_stock_audit_logs_on_part_definition_id_and_recorded_at
    add_check_constraint :stock_audit_logs, "length(trim(reason)) > 0",
                         name: "stock_audit_logs_reason_present"
    add_check_constraint :stock_audit_logs, "change_amount <> 0", name: "stock_audit_logs_change_amount_non_zero"
  end
end
