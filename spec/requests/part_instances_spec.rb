require "rails_helper"

RSpec.describe "Part instances", type: :request do
  def json
    JSON.parse(response.body)
  end

  describe "GET /parts/:part_number/instances" do
    it "returns all instances for the part with pagination meta" do
      part = create(:part_definition, part_number: "HOMER-001")
      create(:part_instance, part_definition: part, serial_number: "HMR-0001")
      create(:part_instance, part_definition: part, serial_number: "HMR-0002")

      get "/parts/HOMER-001/instances"

      expect(response).to have_http_status(:ok)
      serials = json["data"].map { |i| i["serialNumber"] }
      expect(serials).to contain_exactly("HMR-0001", "HMR-0002")
      expect(json["data"].first).to include("partNumber" => "HOMER-001")
      expect(json["data"].first).to have_key("currentStatus")
      expect(json["meta"]).to include("currentPage", "totalPages", "totalCount" => 2)
    end

    it "filters by ?status=" do
      part = create(:part_definition, part_number: "HOMER-001")
      create(:part_instance, part_definition: part, serial_number: "HMR-0001", current_status: "RECEIVED")
      create(:part_instance, part_definition: part, serial_number: "HMR-0002", current_status: "CERTIFIED")

      get "/parts/HOMER-001/instances", params: { status: "CERTIFIED" }

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |i| i["serialNumber"] }).to contain_exactly("HMR-0002")
      expect(json["meta"]["totalCount"]).to eq(1)
    end

    it "does not include instances of a different part" do
      part = create(:part_definition, part_number: "HOMER-001")
      other = create(:part_definition, part_number: "OTHER-001")
      create(:part_instance, part_definition: part, serial_number: "HMR-0001")
      create(:part_instance, part_definition: other, serial_number: "OTH-0001")

      get "/parts/HOMER-001/instances"

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |i| i["serialNumber"] }).to contain_exactly("HMR-0001")
    end

    it "returns 404 when the part does not exist" do
      get "/parts/NOPE-001/instances"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end
end
