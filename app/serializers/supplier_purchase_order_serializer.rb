class SupplierPurchaseOrderSerializer
  include Alba::Resource

  transform_keys :lower_camel

  attributes :id, :supplier_id, :status, :customer_order_id

  has_many :supplier_purchase_order_lines,
           key: :lines,
           resource: SupplierPurchaseOrderLineSerializer

  attribute :created_at do |po|
    po.created_at.utc.iso8601(3)
  end

  attribute :updated_at do |po|
    po.updated_at.utc.iso8601(3)
  end
end
