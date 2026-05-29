SeedHelper.track("Track 1 — Infra & Setup (JAS-5…JAS-10)")

SeedHelper.step("seed harness online — no domain data until Track 2") do
  # Track 1 ships infrastructure only; the data model lands in Track 2.
  # This step exists to prove the pipeline runs green on a fresh database.
  true
end
