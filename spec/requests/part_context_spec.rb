require "rails_helper"

# Request spec for GET /parts/:part_number/context (JAS-45) — the rich,
# self-contained snapshot intended to drop straight into an LLM prompt.
#
# Counts are asserted against the real rows we build (never hardcoded), so the
# spec stays honest if the builder's aggregation drifts. Real PostgreSQL, no
# mocking — the GROUP BY current_status aggregation runs against the DB.
RSpec.describe "Part context", type: :request do
  def json
    JSON.parse(response.body)
  end

  describe "GET /parts/:part_number/context" do
    it "returns a rich camelCase snapshot with accurate aggregate data" do
      part = create(:part_definition, :released, part_number: "THE-HOMER-001", name: "The Homer", revision: "B")

      # Instances across multiple statuses.
      9.times { create(:part_instance, part_definition: part, current_status: "RECEIVED") }
      4.times { create(:part_instance, part_definition: part, current_status: "IN_ASSEMBLY") }
      2.times { create(:part_instance, part_definition: part, current_status: "CERTIFIED") }

      # A BOM child with its own stock.
      horn = create(:part_definition, part_number: "HORN-LCC-001", name: "La Cucaracha Horn")
      create(:stock, part_definition: horn, quantity_on_hand: 50, quantity_reserved: 3)
      create(:bom_item, parent: part, child: horn, quantity: 3)
      # A soft-deleted BOM item that must be excluded.
      gone = create(:part_definition, part_number: "GONE-001", name: "Removed Part")
      create(:bom_item, :deleted, parent: part, child: gone, quantity: 9)

      # Open / partially-received POs with a line for this part (should count),
      # plus a received PO (should not count).
      open_po = create(:supplier_purchase_order, :open)
      create(:supplier_purchase_order_line, supplier_purchase_order: open_po, part_definition: part)
      partial_po = create(:supplier_purchase_order, :partially_received)
      create(:supplier_purchase_order_line, supplier_purchase_order: partial_po, part_definition: part)
      received_po = create(:supplier_purchase_order, :received)
      create(:supplier_purchase_order_line, supplier_purchase_order: received_po, part_definition: part)

      # Lifecycle events across instances; build 6 so we can assert the cap at 5
      # and DESC ordering by occurred_at.
      instances = part.part_instances.order(:created_at).to_a
      base = Time.utc(2026, 5, 28, 10, 0, 0)
      events = 6.times.map do |i|
        create(
          :lifecycle_event,
          part_instance: instances[i % instances.size],
          event_type: "IN_ASSEMBLY",
          actor: "jamie@factory.com",
          notes: "event #{i}",
          occurred_at: base + i.minutes
        )
      end

      get "/parts/THE-HOMER-001/context"

      expect(response).to have_http_status(:ok)

      expect(json["partNumber"]).to eq("THE-HOMER-001")
      expect(json["name"]).to eq("The Homer")
      expect(json["revision"]).to eq("B")
      expect(json["status"]).to eq("RELEASED")

      # Inventory totals match the rows we built.
      expect(json["inventory"]["total"]).to eq(part.part_instances.count)
      expect(json["inventory"]["byStatus"]).to eq(
        "RECEIVED" => 9, "IN_ASSEMBLY" => 4, "CERTIFIED" => 2
      )

      # Summary is templated from the real counts.
      expect(json["summary"]).to eq(
        "The Homer. Rev B released. 15 instances created, 4 in assembly, 2 certified."
      )

      # Only OPEN + PARTIALLY_RECEIVED POs with a line for this part.
      expect(json["openPurchaseOrders"]).to eq(2)

      # BOM excludes the soft-deleted item; stockAvailable = on_hand - reserved.
      expect(json["bom"].size).to eq(1)
      expect(json["bom"].first).to eq(
        "partNumber" => "HORN-LCC-001",
        "name" => "La Cucaracha Horn",
        "quantity" => 3,
        "stockAvailable" => 47
      )

      # recentEvents: last 5, DESC by occurred_at.
      expect(json["recentEvents"].size).to eq(5)
      expect(json["recentEvents"].map { |e| e["notes"] }).to eq(
        events.reverse.first(5).map(&:notes)
      )
      first_event = json["recentEvents"].first
      expect(first_event["eventType"]).to eq("IN_ASSEMBLY")
      expect(first_event["actor"]).to eq("jamie@factory.com")
      expect(first_event).to have_key("serialNumber")
      expect(first_event).to have_key("occurredAt")

      expect(json).to have_key("generatedAt")
    end

    it "renders gracefully when revision is nil" do
      part = create(:part_definition, :draft, part_number: "NOREV-001", name: "No Rev Part", revision: nil)
      create(:part_instance, part_definition: part, current_status: "RECEIVED")

      get "/parts/NOREV-001/context"

      expect(response).to have_http_status(:ok)
      expect(json["revision"]).to be_nil
      expect(json["summary"]).to eq(
        "No Rev Part. Rev — in draft. 1 instances created, 0 in assembly, 0 certified."
      )
    end

    it "reports zeroed aggregates for a part with no instances, BOM, POs, or events" do
      create(:part_definition, :obsolete, part_number: "EMPTY-001", name: "Empty Part", revision: "A")

      get "/parts/EMPTY-001/context"

      expect(response).to have_http_status(:ok)
      expect(json["inventory"]).to eq("total" => 0, "byStatus" => {})
      expect(json["openPurchaseOrders"]).to eq(0)
      expect(json["bom"]).to eq([])
      expect(json["recentEvents"]).to eq([])
      expect(json["summary"]).to eq(
        "Empty Part. Rev A obsolete. 0 instances created, 0 in assembly, 0 certified."
      )
    end

    it "returns a child stockAvailable of 0 when the child has no stock row" do
      part = create(:part_definition, :released, part_number: "PARENT-001", name: "Parent")
      child = create(:part_definition, part_number: "CHILD-001", name: "Child")
      create(:bom_item, parent: part, child: child, quantity: 2)

      get "/parts/PARENT-001/context"

      expect(response).to have_http_status(:ok)
      expect(json["bom"].first["stockAvailable"]).to eq(0)
    end

    it "returns 404 NOT_FOUND for an unknown part" do
      get "/parts/DOES-NOT-EXIST/context"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end
end
