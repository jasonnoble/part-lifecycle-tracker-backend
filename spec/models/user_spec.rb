require 'rails_helper'

RSpec.describe User, type: :model do
  it { should validate_presence_of(:name) }
  it { should validate_presence_of(:email) }
  it { should validate_uniqueness_of(:email) }
  it do
    should define_enum_for(:role).
      with_values(
        salesperson: "salesperson",
        floor_manager: "floor_manager",
        installer: "installer",
        qa_engineer: "qa_engineer",
        site_manager: "site_manager"
      ).
      backed_by_column_of_type(:string).
      without_instance_methods
  end
end
