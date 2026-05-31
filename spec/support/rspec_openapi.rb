# Generates doc/openapi.yaml from request specs when run with OPENAPI=1
# (e.g. `OPENAPI=1 bundle exec rspec`). Without that env var it is inert, so
# the normal suite and CI are unaffected. Regenerate after every API change.
require "rspec/openapi"

RSpec::OpenAPI.title = "Part Lifecycle Tracker API"
RSpec::OpenAPI.application_version = "0.1.0"
RSpec::OpenAPI.info = {
  description: "Tracks aircraft/engine parts from design through manufacture and test. " \
               "Spec is generated from RSpec request specs (no hand-written DSL)."
}
RSpec::OpenAPI.servers = [ { url: "http://localhost:3000" } ]

# Tag timestamp-like fields with the right OpenAPI format.
RSpec::OpenAPI.formats_builder = ->(_example, key) {
  "date-time" if key.to_s.end_with?("_at", "At")
}

# Generated `example` blocks capture live response bodies, which contain
# DB-generated UUIDs and `now()` timestamps — so a naive regenerate diffs every
# run. Normalize those volatile values to fixed placeholders so an unchanged API
# regenerates with no diff (the JAS-60 acceptance criterion) while keeping
# representative examples.
# Unanchored so volatile values are normalized even when embedded in a larger
# string (e.g. a "Couldn't find … id=<uuid>" error message).
RSPEC_OPENAPI_UUID = /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/
RSPEC_OPENAPI_TIMESTAMP = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z/
# FactoryBot default sequences (`name { "Part #{n}" }`, `part_number { "PART-####" }`,
# `supplier_id { "VENDOR-####" }`) leak their counter into captured examples, so the
# doc drifts by spec order.
# Anchored (whole-value) so real names like "The Homer" / "MUZZLE-001" are untouched.
RSPEC_OPENAPI_FACTORY_NAME = /\APart \d+\z/
RSPEC_OPENAPI_FACTORY_PART_NUMBER = /\APART-\d+\z/
RSPEC_OPENAPI_FACTORY_SUPPLIER_ID = /\AVENDOR-\d+\z/

RSPEC_OPENAPI_STABILIZE = lambda do |node|
  case node
  when Hash  then node.transform_values! { |v| RSPEC_OPENAPI_STABILIZE.call(v) }
  when Array then node.map! { |v| RSPEC_OPENAPI_STABILIZE.call(v) }
  when String
    node.gsub(RSPEC_OPENAPI_UUID, "00000000-0000-0000-0000-000000000000")
        .gsub(RSPEC_OPENAPI_TIMESTAMP, "2026-01-01T00:00:00.000Z")
        .gsub(RSPEC_OPENAPI_FACTORY_NAME, "Example Part")
        .gsub(RSPEC_OPENAPI_FACTORY_PART_NUMBER, "PART-0000")
        .gsub(RSPEC_OPENAPI_FACTORY_SUPPLIER_ID, "VENDOR-0000")
  else node
  end
end

RSpec::OpenAPI.post_process_hook = ->(_path, _records, spec) { RSPEC_OPENAPI_STABILIZE.call(spec) }
