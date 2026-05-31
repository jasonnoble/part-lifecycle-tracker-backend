class StockAuditLog < ApplicationRecord
  # Append-only audit trail of stock quantity changes. Rows are never updated or
  # deleted; there is no updated_at column. recorded_at defaults to now() in the
  # DB. change_amount is signed (+ for receipts, - for issues) and constrained to
  # be non-zero by stock_audit_logs_change_amount_non_zero.
  belongs_to :part_definition

  validates :change_amount, numericality: { only_integer: true, other_than: 0 }
  validates :reason, presence: true
end
