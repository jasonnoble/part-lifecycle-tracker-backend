FactoryBot.define do
  factory :customer_order do
    sequence(:customer_name) { |n| "Customer #{format('%04d', n)}" }
    status { "OPEN" }

    trait :open do
      status { "OPEN" }
    end

    trait :in_fulfillment do
      status { "IN_FULFILLMENT" }
    end

    trait :complete do
      status { "COMPLETE" }
    end
  end
end
