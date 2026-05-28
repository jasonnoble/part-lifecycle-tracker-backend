require "rails_helper"

RSpec.describe "Database smoke test" do
  let(:connection) { ActiveRecord::Base.connection }

  it "executes a query against a real connection" do
    expect(connection.select_value("SELECT 1")).to eq(1)
  end

  it "is talking to PostgreSQL" do
    expect(connection.adapter_name).to eq("PostgreSQL")
  end

  it "is connected to the test database" do
    expect(connection.current_database).to eq("part_lifecycle_tracker_test")
  end
end
