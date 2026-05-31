require "rails_helper"

RSpec.describe "BOM", type: :request do
  def json
    JSON.parse(response.body)
  end

  describe "GET /parts/:part_number/bom" do
    it "returns all bom items including soft-deleted ones with dependencies" do
      parent = create(:part_definition, :draft, part_number: "ASSY-001")
      muzzle = create(:part_definition, part_number: "MUZZLE-001", name: "Muzzle")
      dome = create(:part_definition, part_number: "DOME-001", name: "Dome")
      horn = create(:part_definition, part_number: "HORN-LCC-001", name: "La Cucaracha Horn")

      muzzle_item = create(:bom_item, parent: parent, child: muzzle, quantity: 1)
      dome_item = create(:bom_item, parent: parent, child: dome, quantity: 1)
      deleted_item = create(:bom_item, :deleted, parent: parent, child: horn, quantity: 5)
      create(:bom_item_dependency, prerequisite: muzzle_item, dependent: dome_item)

      get "/parts/ASSY-001/bom"

      expect(response).to have_http_status(:ok)
      data = json["data"]
      expect(data.size).to eq(3)

      ids = data.map { |i| i["id"] }
      expect(ids).to include(deleted_item.id)

      deleted = data.find { |i| i["id"] == deleted_item.id }
      expect(deleted["deletedAt"]).not_to be_nil
      expect(deleted["childPartNumber"]).to eq("HORN-LCC-001")

      dome_row = data.find { |i| i["id"] == dome_item.id }
      expect(dome_row["childPartName"]).to eq("Dome")
      expect(dome_row["dependencies"]).to contain_exactly(
        a_hash_including(
          "prerequisiteBomItemId" => muzzle_item.id,
          "prerequisitePartNumber" => "MUZZLE-001"
        )
      )
    end

    it "returns 404 when the parent part does not exist" do
      get "/parts/NOPE-001/bom"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end

  describe "POST /parts/:part_number/bom" do
    it "creates a bom item on a DRAFT part and returns 201" do
      parent = create(:part_definition, :draft, part_number: "ASSY-001")
      create(:part_definition, part_number: "HORN-LCC-001", name: "La Cucaracha Horn")

      expect do
        post "/parts/ASSY-001/bom", params: { childPartNumber: "HORN-LCC-001", quantity: 3 }
      end.to change(BomItem, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json["childPartNumber"]).to eq("HORN-LCC-001")
      expect(json["childPartName"]).to eq("La Cucaracha Horn")
      expect(json["quantity"]).to eq(3)
      expect(json["deletedAt"]).to be_nil
      expect(json["dependencies"]).to eq([])
      expect(BomItem.find(json["id"]).parent).to eq(parent)
    end

    it "embeds dependencies when prerequisites are passed" do
      parent = create(:part_definition, :draft, part_number: "ASSY-001")
      muzzle = create(:part_definition, part_number: "MUZZLE-001", name: "Muzzle")
      create(:part_definition, part_number: "DOME-001", name: "Dome")
      muzzle_item = create(:bom_item, parent: parent, child: muzzle, quantity: 1)

      post "/parts/ASSY-001/bom",
        params: { childPartNumber: "DOME-001", quantity: 1, prerequisites: [ muzzle_item.id ] }

      expect(response).to have_http_status(:created)
      expect(json["dependencies"]).to contain_exactly(
        a_hash_including(
          "prerequisiteBomItemId" => muzzle_item.id,
          "prerequisitePartNumber" => "MUZZLE-001"
        )
      )
      expect(BomItemDependency.count).to eq(1)
    end

    it "returns 422 PART_NOT_DRAFT when the part is released" do
      create(:part_definition, :released, part_number: "REL-001")
      create(:part_definition, part_number: "HORN-LCC-001", name: "Horn")

      expect do
        post "/parts/REL-001/bom", params: { childPartNumber: "HORN-LCC-001", quantity: 1 }
      end.not_to change(BomItem, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("PART_NOT_DRAFT")
    end

    it "returns 422 CHILD_NOT_FOUND when childPartNumber does not exist" do
      create(:part_definition, :draft, part_number: "ASSY-001")

      expect do
        post "/parts/ASSY-001/bom", params: { childPartNumber: "GHOST-999", quantity: 1 }
      end.not_to change(BomItem, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("CHILD_NOT_FOUND")
    end

    it "returns 404 when the parent part does not exist" do
      post "/parts/NOPE-001/bom", params: { childPartNumber: "X", quantity: 1 }

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end

  describe "DELETE /parts/:part_number/bom/:bom_item_id" do
    it "soft deletes and the item still appears in a subsequent GET" do
      parent = create(:part_definition, :draft, part_number: "ASSY-001")
      child = create(:part_definition, part_number: "HORN-LCC-001", name: "Horn")
      item = create(:bom_item, parent: parent, child: child, quantity: 2)

      delete "/parts/ASSY-001/bom/#{item.id}"

      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(item.id)
      expect(json["deletedAt"]).not_to be_nil
      expect(item.reload.deleted_at).not_to be_nil

      get "/parts/ASSY-001/bom"
      expect(json["data"].map { |i| i["id"] }).to include(item.id)
      expect(json["data"].find { |i| i["id"] == item.id }["deletedAt"]).not_to be_nil
    end

    it "returns 404 when the parent part does not exist" do
      delete "/parts/NOPE-001/bom/#{SecureRandom.uuid}"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end

    it "returns 404 when the bom item does not belong to the part" do
      create(:part_definition, :draft, part_number: "ASSY-001")

      delete "/parts/ASSY-001/bom/#{SecureRandom.uuid}"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end
end
