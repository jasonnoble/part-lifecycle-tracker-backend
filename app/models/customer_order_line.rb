class CustomerOrderLine < ApplicationRecord
  belongs_to :customer_order
  belongs_to :part_definition

  validates :quantity, numericality: { greater_than: 0, only_integer: true }
end
