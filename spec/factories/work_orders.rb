FactoryBot.define do
  factory :work_order do
    association :part_definition
    association :part_instance
    status { "OPEN" }
  end
end
