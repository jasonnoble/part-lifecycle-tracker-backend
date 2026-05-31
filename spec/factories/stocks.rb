FactoryBot.define do
  factory :stock do
    association :part_definition
    quantity_on_hand { 0 }
    quantity_reserved { 0 }
  end
end
