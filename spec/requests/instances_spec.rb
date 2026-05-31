require "rails_helper"

RSpec.describe "Instances", type: :request do
  def json
    JSON.parse(response.body)
  end

  describe "GET /instances" do
    it "returns paginated instances with camelCase records and meta" do
      part = create(:part_definition, part_number: "THE-HOMER-001", name: "The Homer")
      create(:part_instance, part_definition: part, serial_number: "HMR-0001")
      create(:part_instance, part_definition: part, serial_number: "HMR-0002")

      get "/instances"

      expect(response).to have_http_status(:ok)
      expect(json["data"].size).to eq(2)
      expect(json["data"].first.keys).to include(
        "id", "partNumber", "serialNumber", "currentStatus", "createdAt", "updatedAt"
      )
      expect(json["data"].first["partNumber"]).to eq("THE-HOMER-001")
      expect(json["meta"]).to include("currentPage" => 1, "totalPages" => 1, "totalCount" => 2)
    end

    it "filters by part_number" do
      homer = create(:part_definition, part_number: "THE-HOMER-001")
      other = create(:part_definition, part_number: "OTHER-001")
      create(:part_instance, part_definition: homer, serial_number: "HMR-0001")
      create(:part_instance, part_definition: other, serial_number: "OTH-0001")

      get "/instances", params: { part_number: "THE-HOMER-001" }

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |i| i["serialNumber"] }).to contain_exactly("HMR-0001")
    end

    it "filters by status" do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      create(:part_instance, part_definition: part, serial_number: "HMR-0001", current_status: "RECEIVED")
      create(:part_instance, part_definition: part, serial_number: "HMR-0002", current_status: "INSTALLED")

      get "/instances", params: { status: "INSTALLED" }

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |i| i["serialNumber"] }).to contain_exactly("HMR-0002")
    end

    it "combines part_number and status filters" do
      homer = create(:part_definition, part_number: "THE-HOMER-001")
      other = create(:part_definition, part_number: "OTHER-001")
      create(:part_instance, part_definition: homer, serial_number: "HMR-0001", current_status: "INSTALLED")
      create(:part_instance, part_definition: homer, serial_number: "HMR-0002", current_status: "RECEIVED")
      create(:part_instance, part_definition: other, serial_number: "OTH-0001", current_status: "INSTALLED")

      get "/instances", params: { part_number: "THE-HOMER-001", status: "INSTALLED" }

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |i| i["serialNumber"] }).to contain_exactly("HMR-0001")
    end
  end

  describe "POST /instances" do
    it "creates an instance at RECEIVED with an initial RECEIVED event" do
      create(:part_definition, part_number: "THE-HOMER-001")

      expect do
        post "/instances", params: { partNumber: "THE-HOMER-001", serialNumber: "HMR-0001" }
      end.to change(PartInstance, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json["serialNumber"]).to eq("HMR-0001")
      expect(json["partNumber"]).to eq("THE-HOMER-001")
      expect(json["currentStatus"]).to eq("RECEIVED")

      instance = PartInstance.find_by(serial_number: "HMR-0001")
      expect(instance.lifecycle_events.count).to eq(1)
      event = instance.lifecycle_events.first
      expect(event.event_type).to eq("RECEIVED")
      expect(event.actor).to eq("system")
      expect(event.occurred_at).to be_present
      expect(event.recorded_at).to be_present
    end

    it "returns 422 when partNumber does not exist" do
      post "/instances", params: { partNumber: "NOPE-001", serialNumber: "HMR-0001" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error", "code")
    end

    it "returns 422 when serialNumber is blank" do
      create(:part_definition, part_number: "THE-HOMER-001")

      post "/instances", params: { partNumber: "THE-HOMER-001", serialNumber: "" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
    end

    it "returns 422 on duplicate serialNumber" do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      create(:part_instance, part_definition: part, serial_number: "HMR-0001")

      post "/instances", params: { partNumber: "THE-HOMER-001", serialNumber: "HMR-0001" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
    end
  end

  describe "GET /instances/:serial" do
    it "returns the instance with derived current_status" do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      create(:part_instance, part_definition: part, serial_number: "HMR-0001", current_status: "INSTALLED")

      get "/instances/HMR-0001"

      expect(response).to have_http_status(:ok)
      expect(json["serialNumber"]).to eq("HMR-0001")
      expect(json["currentStatus"]).to eq("INSTALLED")
    end

    it "returns 404 for an unknown serial" do
      get "/instances/DOES-NOT-EXIST"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end

  describe "GET /instances/:serial/events" do
    it "returns the event log ordered by occurred_at ASC then id" do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      instance = create(:part_instance, part_definition: part, serial_number: "HMR-0001")
      create(:lifecycle_event, :received, part_instance: instance, occurred_at: Time.utc(2026, 5, 28, 10))
      create(:lifecycle_event, :installed, part_instance: instance, occurred_at: Time.utc(2026, 5, 30, 10))
      create(:lifecycle_event, :in_assembly, part_instance: instance, occurred_at: Time.utc(2026, 5, 29, 10))

      get "/instances/HMR-0001/events"

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |e| e["eventType"] }).to eq(%w[RECEIVED IN_ASSEMBLY INSTALLED])
      expect(json["data"].first.keys).to include(
        "id", "eventType", "actor", "notes", "metadata", "occurredAt", "recordedAt"
      )
      expect(json["data"].first.keys).not_to include("updatedAt")
      expect(json["meta"]).to include("currentPage" => 1, "totalCount" => 3)
    end

    # openapi: false on the ordering/pagination edge cases below — they share the
    # GET events path/status with the canonical example above and would otherwise
    # overwrite that nicer multi-status example in the generated doc.
    it "orders a backdated event ahead of an earlier-created but later-occurring event", openapi: false do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      instance = create(:part_instance, part_definition: part, serial_number: "HMR-0001")
      # Created first, but occurred later in real-world time.
      create(:lifecycle_event, part_instance: instance, event_type: "INSTALLED",
                               occurred_at: Time.utc(2026, 5, 30, 10))
      # Created second, but backdated to an earlier real-world time.
      create(:lifecycle_event, part_instance: instance, event_type: "RECEIVED",
                               occurred_at: Time.utc(2026, 5, 28, 10))

      get "/instances/HMR-0001/events"

      expect(response).to have_http_status(:ok)
      # occurred_at ASC wins over creation order: the backdated RECEIVED comes first.
      expect(json["data"].map { |e| e["eventType"] }).to eq(%w[RECEIVED INSTALLED])
    end

    it "breaks ties on equal occurred_at deterministically across repeated queries", openapi: false do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      instance = create(:part_instance, part_definition: part, serial_number: "HMR-0001")
      tied = Time.utc(2026, 5, 29, 10)
      # Three events sharing the exact same occurred_at; UUID ids are random, so
      # only the (occurred_at, id) tiebreaker can make the order stable.
      3.times { create(:lifecycle_event, part_instance: instance, event_type: "INSPECTED", occurred_at: tied) }

      get "/instances/HMR-0001/events"
      first_order = json["data"].map { |e| e["id"] }

      get "/instances/HMR-0001/events"
      second_order = json["data"].map { |e| e["id"] }

      expect(first_order.size).to eq(3)
      expect(second_order).to eq(first_order)
      # The deterministic order is ascending by id, matching the (occurred_at, id) scope.
      expect(first_order).to eq(first_order.sort)
    end

    it "keeps tied-occurred_at rows stable across paginated page boundaries", openapi: false do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      instance = create(:part_instance, part_definition: part, serial_number: "HMR-0001")
      tied = Time.utc(2026, 5, 29, 10)
      5.times { create(:lifecycle_event, part_instance: instance, event_type: "INSPECTED", occurred_at: tied) }

      get "/instances/HMR-0001/events", params: { page: 1, limit: 3 }
      page_one = json["data"].map { |e| e["id"] }

      get "/instances/HMR-0001/events", params: { page: 2, limit: 3 }
      page_two = json["data"].map { |e| e["id"] }

      # No row dropped or duplicated across the page boundary despite identical occurred_at.
      expect((page_one & page_two)).to be_empty
      expect((page_one + page_two).uniq.size).to eq(5)
    end

    it "returns 404 for an unknown serial" do
      get "/instances/DOES-NOT-EXIST/events"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end

  describe "POST /instances/:serial/events" do
    it "appends an event and updates current_status to the new event type" do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      instance = create(:part_instance, part_definition: part, serial_number: "HMR-0001", current_status: "RECEIVED")

      expect do
        post "/instances/HMR-0001/events", params: {
          eventType: "IN_ASSEMBLY",
          actor: "tech@factory.com",
          notes: "Started assembly",
          occurredAt: "2026-05-29T10:00:00Z",
          metadata: { station: "A" }
        }
      end.to change { instance.lifecycle_events.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(json["eventType"]).to eq("IN_ASSEMBLY")
      expect(json["actor"]).to eq("tech@factory.com")
      expect(json["occurredAt"]).to eq("2026-05-29T10:00:00.000Z")
      expect(json["recordedAt"]).to be_present
      expect(instance.reload.current_status).to eq("IN_ASSEMBLY")

      # Both timestamps land on the row: client-supplied occurred_at and server-set recorded_at.
      event = instance.lifecycle_events.order(:recorded_at).last
      expect(event.occurred_at).to eq(Time.utc(2026, 5, 29, 10))
      expect(event.recorded_at).to be_present
      expect(event.recorded_at.utc.year).to eq(Time.current.utc.year)
    end

    it "sets recorded_at server-side and ignores a client-supplied recordedAt" do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      instance = create(:part_instance, part_definition: part, serial_number: "HMR-0001")
      client_recorded = "2000-01-01T00:00:00Z"

      post "/instances/HMR-0001/events", params: {
        eventType: "INSPECTED",
        actor: "qa@factory.com",
        occurredAt: "2026-05-29T10:00:00Z",
        recordedAt: client_recorded
      }

      expect(response).to have_http_status(:created)
      event = instance.lifecycle_events.order(:recorded_at).last
      expect(event.recorded_at).to be > Time.utc(2020, 1, 1)
      expect(event.recorded_at.utc.year).to eq(Time.current.utc.year)
    end

    it "returns 422 for an invalid eventType" do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      create(:part_instance, part_definition: part, serial_number: "HMR-0001")

      post "/instances/HMR-0001/events", params: {
        eventType: "BOGUS",
        actor: "tech@factory.com",
        occurredAt: "2026-05-29T10:00:00Z"
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
    end

    it "returns 422 when occurredAt is missing" do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      create(:part_instance, part_definition: part, serial_number: "HMR-0001")

      post "/instances/HMR-0001/events", params: {
        eventType: "INSPECTED",
        actor: "tech@factory.com"
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
    end

    it "returns 404 for an unknown serial" do
      post "/instances/DOES-NOT-EXIST/events", params: {
        eventType: "INSPECTED",
        actor: "tech@factory.com",
        occurredAt: "2026-05-29T10:00:00Z"
      }

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end
end
