require "rails_helper"

RSpec.describe "Test Records", type: :request do
  def json
    JSON.parse(response.body)
  end

  describe "GET /instances/:serial/tests" do
    it "returns the test records ordered by occurred_at DESC with camelCase records and meta" do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      instance = create(:part_instance, part_definition: part, serial_number: "HMR-0001")
      create(:test_record, part_instance: instance, test_type: "FIRST",
                           occurred_at: Time.utc(2026, 5, 28, 10))
      create(:test_record, part_instance: instance, test_type: "THIRD",
                           occurred_at: Time.utc(2026, 5, 30, 10))
      create(:test_record, part_instance: instance, test_type: "SECOND",
                           occurred_at: Time.utc(2026, 5, 29, 10))

      get "/instances/HMR-0001/tests"

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |t| t["testType"] }).to eq(%w[THIRD SECOND FIRST])
      expect(json["data"].first.keys).to include(
        "id", "testType", "result", "notes", "conductedBy", "occurredAt", "recordedAt"
      )
      expect(json["data"].first.keys).not_to include("updatedAt")
      expect(json["meta"]).to include("currentPage" => 1, "totalPages" => 1, "totalCount" => 3)
    end

    it "returns 404 for an unknown serial" do
      get "/instances/DOES-NOT-EXIST/tests"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end

  describe "POST /instances/:serial/tests" do
    it "records a PASS test and returns 201" do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      instance = create(:part_instance, part_definition: part, serial_number: "HMR-0001")

      expect do
        post "/instances/HMR-0001/tests", params: {
          testType: "HORN_SEQUENCE",
          result: "PASS",
          notes: "All 7 bars played",
          conductedBy: "qa@factory.com",
          occurredAt: "2026-05-28T14:00:00Z"
        }
      end.to change { instance.test_records.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(json["testType"]).to eq("HORN_SEQUENCE")
      expect(json["result"]).to eq("PASS")
      expect(json["notes"]).to eq("All 7 bars played")
      expect(json["conductedBy"]).to eq("qa@factory.com")
      expect(json["occurredAt"]).to eq("2026-05-28T14:00:00.000Z")
      expect(json["recordedAt"]).to be_present
      expect(json.keys).not_to include("updatedAt")
    end

    it "sets recorded_at server-side and ignores a client-supplied recordedAt" do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      instance = create(:part_instance, part_definition: part, serial_number: "HMR-0001")

      post "/instances/HMR-0001/tests", params: {
        testType: "HORN_SEQUENCE",
        result: "PASS",
        conductedBy: "qa@factory.com",
        occurredAt: "2026-05-28T14:00:00Z",
        recordedAt: "2000-01-01T00:00:00Z"
      }

      expect(response).to have_http_status(:created)
      record = instance.test_records.last
      expect(record.recorded_at).to be > Time.utc(2020, 1, 1)
      expect(record.recorded_at.utc.year).to eq(Time.current.utc.year)
    end

    it "returns 422 for an invalid result enum" do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      create(:part_instance, part_definition: part, serial_number: "HMR-0001")

      post "/instances/HMR-0001/tests", params: {
        testType: "HORN_SEQUENCE",
        result: "BOGUS",
        conductedBy: "qa@factory.com",
        occurredAt: "2026-05-28T14:00:00Z"
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
    end

    it "returns 422 when a required field is missing" do
      part = create(:part_definition, part_number: "THE-HOMER-001")
      create(:part_instance, part_definition: part, serial_number: "HMR-0001")

      post "/instances/HMR-0001/tests", params: {
        result: "PASS",
        conductedBy: "qa@factory.com",
        occurredAt: "2026-05-28T14:00:00Z"
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
    end

    it "returns 404 for an unknown serial" do
      post "/instances/DOES-NOT-EXIST/tests", params: {
        testType: "HORN_SEQUENCE",
        result: "PASS",
        conductedBy: "qa@factory.com",
        occurredAt: "2026-05-28T14:00:00Z"
      }

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end
end
