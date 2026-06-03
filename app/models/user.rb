class User < ApplicationRecord
  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
  validates :stytch_user_id, uniqueness: true, allow_nil: true

  enum :role,
       {
         salesperson: "salesperson",
         floor_manager: "floor_manager",
         installer: "installer",
         qa_engineer: "qa_engineer",
         site_manager: "site_manager"
       }, instance_methods: false, validate: true
end
