FactoryBot.define do
  factory :test_record do
    association :part_instance
    test_type { "HORN_SEQUENCE" }
    result { "PASS" }
    notes { nil }
    conducted_by { "qa@factory.com" }
    occurred_at { Time.current }

    trait :failed do
      result { "FAIL" }
    end

    trait :inconclusive do
      result { "INCONCLUSIVE" }
    end
  end
end
