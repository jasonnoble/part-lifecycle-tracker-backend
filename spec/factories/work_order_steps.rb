FactoryBot.define do
  factory :work_order_step do
    association :work_order
    association :bom_item
    status { "PENDING" }
  end
end
