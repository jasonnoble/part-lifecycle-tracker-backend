require "rails_helper"

RSpec.describe "Part status transitions", type: :request do
  def json
    JSON.parse(response.body)
  end

  describe "POST /parts/:part_number/status" do
    it "transitions DRAFT -> RELEASED with 200 and the serialized part" do
      create(:part_definition, :draft, part_number: "ST-001", name: "Drafty")

      post "/parts/ST-001/status", params: { status: "RELEASED" }

      expect(response).to have_http_status(:ok)
      expect(json["partNumber"]).to eq("ST-001")
      expect(json["status"]).to eq("RELEASED")
      expect(json.keys).to include("id", "partNumber", "status", "createdAt", "updatedAt")
      expect(PartDefinition.find_by(part_number: "ST-001").status).to eq("RELEASED")
    end

    it "transitions RELEASED -> OBSOLETE with 200" do
      create(:part_definition, :released, part_number: "ST-002")

      post "/parts/ST-002/status", params: { status: "OBSOLETE" }

      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("OBSOLETE")
      expect(PartDefinition.find_by(part_number: "ST-002").status).to eq("OBSOLETE")
    end

    it "transitions DRAFT -> OBSOLETE with 200" do
      create(:part_definition, :draft, part_number: "ST-003")

      post "/parts/ST-003/status", params: { status: "OBSOLETE" }

      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("OBSOLETE")
      expect(PartDefinition.find_by(part_number: "ST-003").status).to eq("OBSOLETE")
    end

    it "rejects RELEASED -> DRAFT with 422 INVALID_TRANSITION" do
      create(:part_definition, :released, part_number: "ST-004")

      post "/parts/ST-004/status", params: { status: "DRAFT" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("INVALID_TRANSITION")
      expect(json["error"]).to include("RELEASED")
      expect(json["error"]).to include("DRAFT")
      expect(PartDefinition.find_by(part_number: "ST-004").status).to eq("RELEASED")
    end

    it "rejects OBSOLETE -> RELEASED with 422 INVALID_TRANSITION (terminal state)" do
      create(:part_definition, :obsolete, part_number: "ST-005")

      post "/parts/ST-005/status", params: { status: "RELEASED" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("INVALID_TRANSITION")
      expect(json["error"]).to include("OBSOLETE")
      expect(json["error"]).to include("RELEASED")
      expect(PartDefinition.find_by(part_number: "ST-005").status).to eq("OBSOLETE")
    end

    it "rejects an unrecognized status string with 422 INVALID_TRANSITION" do
      create(:part_definition, :draft, part_number: "ST-006")

      post "/parts/ST-006/status", params: { status: "BOGUS" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("INVALID_TRANSITION")
      expect(json["error"]).to include("DRAFT")
      expect(json["error"]).to include("BOGUS")
      expect(PartDefinition.find_by(part_number: "ST-006").status).to eq("DRAFT")
    end

    it "returns 404 NOT_FOUND for a missing part" do
      post "/parts/NOPE-999/status", params: { status: "RELEASED" }

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end
end
