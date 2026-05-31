FactoryBot.define do
  factory :part_definition do
    sequence(:part_number) { |n| "PART-#{format('%04d', n)}" }
    sequence(:name) { |n| "Part #{n}" }
    description { "A part definition for testing." }
    revision { "A" }
    status { "DRAFT" }

    trait :draft do
      status { "DRAFT" }
    end

    trait :released do
      status { "RELEASED" }
    end

    trait :obsolete do
      status { "OBSOLETE" }
    end
  end
end
