FactoryBot.define do
  factory :supplier_purchase_order_line do
    association :supplier_purchase_order
    association :part_definition
    quantity { 50 }
    quantity_received { 0 }
    status { "NEEDS_ORDERING" }

    trait :ordered do
      status { "ORDERED" }
    end

    trait :partially_received do
      status { "PARTIALLY_RECEIVED" }
      quantity_received { 10 }
    end

    trait :received do
      status { "RECEIVED" }
      quantity_received { 50 }
    end
  end
end
