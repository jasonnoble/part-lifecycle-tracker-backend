require "rails_helper"

RSpec.describe "Parts", type: :request do
  def json
    JSON.parse(response.body)
  end

  describe "GET /parts" do
    it "returns all parts with camelCase records and pagination meta" do
      create(:part_definition, part_number: "AAA-001", name: "Alpha")
      create(:part_definition, part_number: "BBB-002", name: "Beta")

      get "/parts"

      expect(response).to have_http_status(:ok)
      expect(json["data"].size).to eq(2)
      expect(json["data"].first.keys).to include(
        "id", "partNumber", "name", "description", "revision", "status", "createdAt", "updatedAt"
      )
      expect(json["meta"]).to include(
        "currentPage" => 1,
        "totalPages" => 1,
        "totalCount" => 2
      )
    end

    it "filters by status" do
      create(:part_definition, :released, part_number: "REL-001")
      create(:part_definition, :draft, part_number: "DRF-001")

      get "/parts", params: { status: "RELEASED" }

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |p| p["partNumber"] }).to contain_exactly("REL-001")
    end

    it "filters by search term across name and part_number (case-insensitive)" do
      create(:part_definition, part_number: "THE-HOMER-001", name: "The Homer")
      create(:part_definition, part_number: "MARGE-FAM-001", name: "Marge's Cruiser")

      get "/parts", params: { search: "homer" }

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |p| p["partNumber"] }).to contain_exactly("THE-HOMER-001")
    end

    it "combines status and search filters" do
      create(:part_definition, :released, part_number: "THE-HOMER-001", name: "The Homer")
      create(:part_definition, :draft, part_number: "HOMER-DRAFT-001", name: "Homer Draft")

      get "/parts", params: { status: "RELEASED", search: "homer" }

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |p| p["partNumber"] }).to contain_exactly("THE-HOMER-001")
    end

    it "paginates across pages, exposing accurate meta" do
      create(:part_definition, part_number: "PG-001")
      create(:part_definition, part_number: "PG-002")
      create(:part_definition, part_number: "PG-003")

      get "/parts", params: { limit: 2 }

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |p| p["partNumber"] }).to eq(%w[PG-001 PG-002])
      expect(json["meta"]).to include("currentPage" => 1, "totalPages" => 2, "totalCount" => 3)

      get "/parts", params: { limit: 2, page: 2 }

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |p| p["partNumber"] }).to eq(%w[PG-003])
      expect(json["meta"]).to include("currentPage" => 2, "totalPages" => 2, "totalCount" => 3)
    end

    it "returns an empty data array with meta when there are no parts" do
      get "/parts"

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to eq([])
      expect(json["meta"]).to include("currentPage" => 1, "totalCount" => 0)
    end
  end

  describe "POST /parts" do
    it "creates a part and returns 201 with the record" do
      expect do
        post "/parts", params: { part_number: "NEW-001", name: "New Part", description: "desc", revision: "A" }
      end.to change(PartDefinition, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json["partNumber"]).to eq("NEW-001")
      expect(json["status"]).to eq("DRAFT")
    end

    it "returns 422 when a required field is missing" do
      post "/parts", params: { description: "no name or part_number" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error", "code")
    end

    it "returns 422 on duplicate part_number" do
      create(:part_definition, part_number: "DUP-001")

      post "/parts", params: { part_number: "DUP-001", name: "Dupe" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
    end
  end

  describe "GET /parts/:part_number" do
    it "returns the part by part_number" do
      create(:part_definition, part_number: "FIND-001", name: "Findable")

      get "/parts/FIND-001"

      expect(response).to have_http_status(:ok)
      expect(json["partNumber"]).to eq("FIND-001")
      expect(json["name"]).to eq("Findable")
    end

    it "returns 404 with error shape when not found" do
      get "/parts/DOES-NOT-EXIST"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end

  describe "PATCH /parts/:part_number" do
    it "updates name and description on a DRAFT part" do
      create(:part_definition, :draft, part_number: "UPD-001", name: "Old")

      patch "/parts/UPD-001", params: { name: "New Name", description: "New desc" }

      expect(response).to have_http_status(:ok)
      expect(json["name"]).to eq("New Name")
      expect(json["description"]).to eq("New desc")
    end

    it "allows changing revision on a DRAFT part" do
      create(:part_definition, :draft, part_number: "UPD-002", revision: "A")

      patch "/parts/UPD-002", params: { revision: "B" }

      expect(response).to have_http_status(:ok)
      expect(json["revision"]).to eq("B")
    end

    it "returns 422 REVISION_LOCKED when changing revision on a non-DRAFT part" do
      create(:part_definition, :released, part_number: "UPD-003", revision: "A")

      patch "/parts/UPD-003", params: { revision: "B" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("REVISION_LOCKED")
      expect(PartDefinition.find_by(part_number: "UPD-003").revision).to eq("A")
    end

    it "ignores a status param without erroring" do
      create(:part_definition, :draft, part_number: "UPD-004")

      patch "/parts/UPD-004", params: { name: "Renamed", status: "RELEASED" }

      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("DRAFT")
      expect(json["name"]).to eq("Renamed")
    end

    it "returns 404 when the part does not exist" do
      patch "/parts/NOPE-001", params: { name: "x" }

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end
end
