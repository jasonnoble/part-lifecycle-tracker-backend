SeedHelper.track("Track 4 — Part Instances + lifecycle events (JAS-29)")

# Track 4 seeds physical Part Instances of THE-HOMER-001, each with an
# append-only lifecycle history. current_status is always the latest event's
# type — we build the history then set current_status from it, mirroring how the
# real append handler behaves (create lifecycle_event, then update
# current_status).
#
# Idempotency is the hard part for an append-only log: re-running must never
# duplicate part_instances OR lifecycle_events. We guard by
# find_or_create_by(serial_number:) for the instance, and only append events
# the instance doesn't already have (we treat the desired event sequence as the
# source of truth and skip any event_type already present for that instance).

# HOMER_PART_NUMBER is already defined by an earlier track; reuse it.
HOMER_PART_NUMBER = "THE-HOMER-001" unless defined?(HOMER_PART_NUMBER)

# Each instance's desired lifecycle history, in chronological order. The last
# event's type is the instance's current_status.
HOMER_INSTANCES = {
  "HMR-0001" => %w[RECEIVED],
  "HMR-0002" => %w[RECEIVED],
  "HMR-0003" => %w[RECEIVED],
  "HMR-0004" => %w[RECEIVED],
  "HMR-0005" => %w[RECEIVED],
  "HMR-0006" => %w[RECEIVED IN_ASSEMBLY],
  "HMR-0007" => %w[RECEIVED IN_ASSEMBLY],
  "HMR-0008" => %w[RECEIVED IN_ASSEMBLY INSTALLED],
  "HMR-0009" => %w[RECEIVED IN_ASSEMBLY INSTALLED VALIDATED],
  # The demo unit: a complete lifecycle history through CERTIFIED, with an
  # event for every step in the v0 sequence.
  "HMR-0047" => %w[RECEIVED INSPECTED IN_ASSEMBLY INSTALLED VALIDATED CERTIFIED]
}.freeze

# Distinct actors per event type so the four-eyes principle reads true in the
# seed data (installer != validator != certifier).
EVENT_ACTORS = {
  "RECEIVED"    => "receiving@factory.example",
  "INSPECTED"   => "inspector@factory.example",
  "IN_ASSEMBLY" => "assembly@factory.example",
  "INSTALLED"   => "installer@factory.example",
  "VALIDATED"   => "validator@factory.example",
  "CERTIFIED"   => "qa@factory.example"
}.freeze

# Deterministic, ordered occurred_at timestamps so reseeding is stable and the
# event log reads as a believable timeline. Each instance's events are spaced
# one hour apart, starting from a per-instance base day.
INSTANCE_EPOCH = Time.utc(2026, 1, 5, 9, 0, 0)

homer = PartDefinition.find_by!(part_number: HOMER_PART_NUMBER)

received_count = 0

SeedHelper.step("seed #{HOMER_INSTANCES.size} The Homer instances + lifecycle events") do
  HOMER_INSTANCES.each_with_index do |(serial_number, sequence), instance_index|
    # The instance starts life at its first event; current_status is corrected
    # below once the full history is in place.
    instance = PartInstance.find_or_create_by!(serial_number: serial_number) do |pi|
      pi.part_definition = homer
      pi.current_status  = sequence.first
    end

    received_count += 1 if sequence.include?("RECEIVED")

    existing_event_types = instance.lifecycle_events.pluck(:event_type).to_set
    base_time = INSTANCE_EPOCH + (instance_index * 1.day)

    sequence.each_with_index do |event_type, step_index|
      next if existing_event_types.include?(event_type)

      instance.lifecycle_events.create!(
        event_type:  event_type,
        actor:       EVENT_ACTORS.fetch(event_type),
        occurred_at: base_time + (step_index * 1.hour),
        notes:       "Seed: #{serial_number} reached #{event_type}."
      )
    end

    # current_status is derived from the latest event — set it from the desired
    # sequence's terminal state (idempotent: equals itself on reseed).
    desired_status = sequence.last
    instance.update!(current_status: desired_status) unless instance.current_status == desired_status
  end
end

AUDIT_REASON = "Seed Track 4: received #{received_count} The Homer instances".freeze

SeedHelper.step("set The Homer stock quantity_on_hand to #{received_count} (received instances)") do
  stock = Stock.find_or_create_by!(part_definition_id: homer.id) do |s|
    s.quantity_on_hand = 0
    s.quantity_reserved = 0
  end

  # Idempotent: always converge on received_count. (An earlier track resets
  # Homer stock to 0 on every full reseed, so we set it explicitly rather than
  # trusting the current value.)
  stock.update!(quantity_on_hand: received_count) unless stock.quantity_on_hand == received_count

  # Record the change so on-hand history is auditable. There is no StockAuditLog
  # model yet, so we read/insert the table directly. We write at most ONE
  # Track-4 audit row per part: guard on an existing row with our reason so
  # reseeds never accumulate duplicate audit entries. change_amount must be
  # non-zero (DB constraint), so we only write a row when there are instances.
  already_audited = ActiveRecord::Base.connection.select_value(
    ActiveRecord::Base.sanitize_sql_array(
      [ "SELECT 1 FROM stock_audit_logs WHERE part_definition_id = ? AND reason = ? LIMIT 1", homer.id, AUDIT_REASON ]
    )
  )

  if received_count.positive? && already_audited.nil?
    ActiveRecord::Base.connection.insert(
      ActiveRecord::Base.sanitize_sql_array(
        [ "INSERT INTO stock_audit_logs (part_definition_id, change_amount, reason) VALUES (?, ?, ?)",
          homer.id, received_count, AUDIT_REASON ]
      )
    )
  end
end
