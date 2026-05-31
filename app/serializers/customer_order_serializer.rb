class CustomerOrderSerializer
  include Alba::Resource

  transform_keys :lower_camel

  attributes :id, :customer_name, :status

  has_many :customer_order_lines,
           key: :lines,
           resource: CustomerOrderLineSerializer

  attribute :created_at do |co|
    co.created_at.utc.iso8601(3)
  end

  attribute :updated_at do |co|
    co.updated_at.utc.iso8601(3)
  end
end
