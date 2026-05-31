FactoryBot.define do
  factory :supplier_purchase_order do
    sequence(:supplier_id) { |n| "VENDOR-#{format('%04d', n)}" }
    status { "OPEN" }

    trait :open do
      status { "OPEN" }
    end

    trait :partially_received do
      status { "PARTIALLY_RECEIVED" }
    end

    trait :received do
      status { "RECEIVED" }
    end

    trait :closed do
      status { "CLOSED" }
    end
  end
end
