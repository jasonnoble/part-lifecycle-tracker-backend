SeedHelper.track("Track 8 — Full /context demo dataset (JAS-48)")

# Track 8 makes GET /parts/THE-HOMER-001/context return a compelling, non-trivial
# snapshot. It is the LAST track to run (sorted filename), so it can safely set
# child stock AFTER Track 2 zeroes it on a full reseed.
#
# Everything here is idempotent and reaches a fixed TARGET END STATE:
#   * a fixed roster of THE-HOMER-001 part instances (by serial_number), each at
#     a known current_status with a matching append-only lifecycle-event chain;
#   * non-zero stock on every BOM child (so bom[].stockAvailable is meaningful);
#   * one OPEN supplier PO carrying a line for THE-HOMER-001 (openPurchaseOrders >= 1).
#
# Re-running must NOT duplicate instances, events, stock-audit rows, or POs.
# We never assume other tracks' instance seeds ran on this branch.

HOMER_CONTEXT_PART_NUMBER = "THE-HOMER-001"

# Fixed roster: serial_number => target current_status. The chosen mix gives the
# summary non-zero counts for many statuses and clears the JAS-48 minimums
# (>= 5 RECEIVED, >= 4 IN_ASSEMBLY, >= 2 CERTIFIED; >= 15 instances total).
HOMER_INSTANCE_ROSTER = {
  # 2 ORDERED (on a supplier PO, not yet received)
  "HMR-0001" => "ORDERED",
  "HMR-0002" => "ORDERED",
  # 5 RECEIVED
  "HMR-0003" => "RECEIVED",
  "HMR-0004" => "RECEIVED",
  "HMR-0005" => "RECEIVED",
  "HMR-0006" => "RECEIVED",
  "HMR-0007" => "RECEIVED",
  # 1 INSPECTED
  "HMR-0008" => "INSPECTED",
  # 4 IN_ASSEMBLY
  "HMR-0009" => "IN_ASSEMBLY",
  "HMR-0010" => "IN_ASSEMBLY",
  "HMR-0011" => "IN_ASSEMBLY",
  "HMR-0012" => "IN_ASSEMBLY",
  # 2 INSTALLED
  "HMR-0013" => "INSTALLED",
  "HMR-0014" => "INSTALLED",
  # 1 VALIDATED
  "HMR-0015" => "VALIDATED",
  # 2 CERTIFIED
  "HMR-0016" => "CERTIFIED",
  "HMR-0017" => "CERTIFIED"
}.freeze

# Lifecycle pipeline order. An instance at status S has one event for every
# status up to and including S (a realistic append-only history), which also
# populates recentEvents richly.
LIFECYCLE_PIPELINE = PartInstance::STATUSES # ORDERED..CERTIFIED, in order

# Non-zero on-hand stock per BOM child so stockAvailable reads well in /context.
HOMER_CHILD_STOCK = {
  "HORN-LCC-001"   => { quantity_on_hand: 120, quantity_reserved: 9 },
  "DOME-TRANS-001" => { quantity_on_hand: 64,  quantity_reserved: 4 },
  "MUZZLE-001"     => { quantity_on_hand: 80,  quantity_reserved: 5 },
  "ENGINE-V8-001"  => { quantity_on_hand: 52,  quantity_reserved: 3 }
}.freeze

# Stable marker so the demo PO is found (not re-created) on every run.
HOMER_PO_SUPPLIER_ID = "ACME-SPRINGFIELD"
HOMER_PO_LINE_QTY = 25

# Backdate events from this anchor so occurred_at ordering is deterministic and
# "recent". Each instance's chain is spread out in minutes by its index.
EVENT_ANCHOR = Time.utc(2026, 5, 28, 9, 0, 0)

# A certified instance carries a realistic QA test history so the InstanceDetail
# "Test Records" section (JAS-70) renders populated instead of "No test records."
# Tells a fix-and-retest story and exercises every result badge: an initial FAIL,
# its PASS retest, an INCONCLUSIVE re-run, and a final PASS sign-off.
HOMER_TEST_RECORD_SERIAL = "HMR-0016" # one of the two CERTIFIED instances above
HOMER_QA = "dr.quinn@example.com"     # Dr. Quinn, qa_engineer (seeded user)
HOMER_TEST_RECORDS = [
  { test_type: "HORN_SEQUENCE", result: "FAIL",
    occurred_at: Time.utc(2026, 5, 26, 13, 0, 0),
    notes: "La Cucaracha bar 4 muted; horn diaphragm reseated." },
  { test_type: "HORN_SEQUENCE", result: "PASS",
    occurred_at: Time.utc(2026, 5, 26, 15, 30, 0),
    notes: "Retest after diaphragm reseat; all 7 bars clean." },
  { test_type: "DOME_PRESSURE", result: "PASS",
    occurred_at: Time.utc(2026, 5, 27, 9, 0, 0),
    notes: "Transparent dome held 1.5 atm for 30 min, no leak." },
  { test_type: "EMISSIONS", result: "INCONCLUSIVE",
    occurred_at: Time.utc(2026, 5, 27, 11, 0, 0),
    notes: "V8 emissions analyzer faulted mid-run; flagged for re-run." },
  { test_type: "FINAL_QA", result: "PASS",
    occurred_at: Time.utc(2026, 5, 27, 16, 0, 0),
    notes: "Full functional sign-off ahead of certification." }
].freeze

homer = PartDefinition.find_by!(part_number: HOMER_CONTEXT_PART_NUMBER)

SeedHelper.step("seed #{HOMER_INSTANCE_ROSTER.size} The Homer instances (idempotent by serial_number)") do
  HOMER_INSTANCE_ROSTER.each_with_index do |(serial_number, target_status), idx|
    instance = PartInstance.find_or_create_by!(serial_number: serial_number) do |pi|
      pi.part_definition = homer
      pi.current_status  = target_status
    end

    # Reconcile current_status without ever duplicating the instance.
    instance.update!(current_status: target_status) unless instance.current_status == target_status

    # Append the full event chain ONLY if this instance has no events yet, so a
    # re-run never appends to the immutable log again.
    next if instance.lifecycle_events.exists?

    chain = LIFECYCLE_PIPELINE[0..LIFECYCLE_PIPELINE.index(target_status)]
    base  = EVENT_ANCHOR + (idx * 7).minutes
    events = chain.each_with_index.map do |event_type, step|
      {
        part_instance_id: instance.id,
        event_type: event_type,
        actor: "jamie.torres@example.com",
        occurred_at: base + (step * 1).minutes,
        notes: "#{serial_number} -> #{event_type}"
      }
    end
    LifecycleEvent.insert_all(events)
  end
end

SeedHelper.step("seed #{HOMER_TEST_RECORDS.size} test records on #{HOMER_TEST_RECORD_SERIAL} (incl. a FAIL)") do
  instance = PartInstance.find_by!(serial_number: HOMER_TEST_RECORD_SERIAL)

  # test_records is append-only with no natural unique key, so guard on existence
  # (same pattern as the lifecycle-event chain above): only write the history when
  # this instance has none yet, so a re-run never appends duplicates.
  next if instance.test_records.exists?

  rows = HOMER_TEST_RECORDS.map do |attrs|
    { part_instance_id: instance.id, conducted_by: HOMER_QA, **attrs }
  end
  TestRecord.insert_all(rows)
end

SeedHelper.step("set non-zero stock on The Homer's BOM children (after Track 2 reset)") do
  children = PartDefinition.where(part_number: HOMER_CHILD_STOCK.keys).index_by(&:part_number)
  rows = HOMER_CHILD_STOCK.map do |part_number, levels|
    { part_definition_id: children.fetch(part_number).id, **levels }
  end
  Stock.upsert_all(rows, unique_by: :part_definition_id)
end

SeedHelper.step("seed a stock-receipt audit row per BOM child (guarded)") do
  children = PartDefinition.where(part_number: HOMER_CHILD_STOCK.keys).index_by(&:part_number)
  HOMER_CHILD_STOCK.each do |part_number, levels|
    part_definition_id = children.fetch(part_number).id
    reason = "Track 8 demo receipt"
    next if StockAuditLog.exists?(part_definition_id: part_definition_id, reason: reason)

    StockAuditLog.create!(
      part_definition_id: part_definition_id,
      change_amount: levels[:quantity_on_hand],
      reason: reason
    )
  end
end

SeedHelper.step("seed one OPEN supplier PO with a line for The Homer (idempotent)") do
  po = SupplierPurchaseOrder.find_or_create_by!(supplier_id: HOMER_PO_SUPPLIER_ID) do |new_po|
    new_po.status = "OPEN"
  end

  SupplierPurchaseOrderLine.find_or_create_by!(
    supplier_purchase_order_id: po.id,
    part_definition_id: homer.id
  ) do |line|
    line.quantity = HOMER_PO_LINE_QTY
    line.quantity_received = 0
    line.status = "ORDERED"
  end
end
