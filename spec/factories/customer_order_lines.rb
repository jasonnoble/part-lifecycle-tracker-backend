FactoryBot.define do
  factory :customer_order_line do
    association :customer_order
    association :part_definition
    quantity { 5 }
  end
end
