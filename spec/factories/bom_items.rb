FactoryBot.define do
  factory :bom_item do
    association :parent, factory: :part_definition
    association :child, factory: :part_definition
    quantity { 1 }

    trait :deleted do
      deleted_at { Time.current }
    end
  end
end
