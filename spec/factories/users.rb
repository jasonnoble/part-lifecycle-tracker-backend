FactoryBot.define do
  factory :user do
    traits_for_enum :role, {
      salesperson: "salesperson",
      floor_manager: "floor_manager",
      installer: "installer",
      qa_engineer: "qa_engineer",
      site_manager: "site_manager"
    }
    email { Faker::Internet.email(domain: "example.com", name: name) }
    name { Faker::Name.name }
    role { 'installer' }
  end
end
