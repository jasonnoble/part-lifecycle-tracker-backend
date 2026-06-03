SeedHelper.track("Track 6 — Work Orders in various states (JAS-40)")

# Track 6 seeds three work orders against THE-HOMER-001 that span the full
# work_orders status range, so the API/UI has realistic fixtures to render:
#
#   WO-0001 — COMPLETE : HMR-0047, every step CERTIFIED with a full four-eyes
#                        installer/validator/certifier history. The "demo
#                        completed unit."
#   WO-0002 — OPEN     : HMR-0006, mid-build — some steps INSTALLED, one BLOCKED
#                        (to exercise the blocked-step UI), the rest PENDING.
#   WO-0003 — BLOCKED  : HMR-0007, work order itself BLOCKED waiting on stock.
#
# IMPORTANT — this seed does NOT assume Track 4's instance seed has run on this
# branch. The part instances it references (HMR-0047/0006/0007) are looked up by
# serial_number and created minimally if absent, without re-writing any lifecycle
# history an earlier track may already own. This keeps Track 6 correct both on
# this branch (no Track 4) and on main (where Track 4 runs first).
#
# Seeds write work_order_steps status/actor/timestamp columns DIRECTLY, bypassing
# the AASM transitions — that is the normal seeding pattern here (other tracks
# write status verbatim too). The schema has no human-readable WO number column,
# so "WO-0001" etc. are labels; a work order's identity is its part_instance_id
# (one open build per physical serial).

# Seeded personas. Installer and validator/certifier are always distinct so the
# work_order_steps_four_eyes CHECK (validated_actor <> installed_actor) holds.
INSTALLER = "jamie@factory.com" # Jamie Torres, assembly technician
VALIDATOR = "riley@factory.com" # Riley Park, validation technician
QA = "quinn@factory.com" # Dr. Quinn, QA / certifying authority

users = [
  { name: "Sarah Chen", email: "sarah.chen@example.com", role: "salesperson" },
  { name: "Marcus Webb", email: "marcus.webb@example.com", role: "floor_manager" },
  { name: "Jamie Torres", email: "jamie.torres@example.com", role: "installer" },
  { name: "Riley Park", email: "riley.park@example.com", role: "installer" },
  { name: "Dr. Quinn", email: "dr.quinn@example.com", role: "qa_engineer" },
  { name: "Alex Reyes", email: "alex.reyes@example.com", role: "site_manager" }
]

# stytch_user_id is populated out-of-band by StytchUserSync (rails stytch:sync_users),
# not here — seeding stays keyless and makes no external API calls.
SeedHelper.track("  Track 6-1 — Add seeded users")
User.upsert_all(users, unique_by: :email)

homer = PartDefinition.find_by!(part_number: "THE-HOMER-001")

# The Homer's active BOM items, ordered for deterministic step creation. MUZZLE
# is the prerequisite for DOME-TRANS (seeded in Track 2/3); ordering muzzle ahead
# of the dome mirrors the real assembly sequence.
HOMER_STEP_ORDER = %w[MUZZLE-001 DOME-TRANS-001 ENGINE-V8-001 HORN-LCC-001].freeze

homer_bom_items = BomItem.where(parent_part_definition_id: homer.id)
                         .includes(:child)
                         .index_by { |bi| bi.child.part_number }

ordered_bom_items = HOMER_STEP_ORDER.filter_map { |pn| homer_bom_items[pn] }

# --- helpers ---------------------------------------------------------------

# Look up (or minimally create) a Homer part instance by serial, without
# clobbering lifecycle history an earlier track may already have written.
def find_or_create_homer_instance(serial:, status:, homer:)
  PartInstance.find_or_create_by!(serial_number: serial) do |pi|
    pi.part_definition = homer
    pi.current_status = status
  end
end

# Idempotently set a step's denormalized status + four-eyes actor/timestamp
# history. Writes columns directly (seed pattern), so re-running is a no-op once
# the values match.
def set_step!(step, attrs)
  step.update!(attrs) unless attrs.all? { |k, v| step.public_send(k) == v }
end

# --- WO-0001: COMPLETE -----------------------------------------------------

SeedHelper.step("WO-0001 (COMPLETE) — HMR-0047, all steps certified") do
  instance = find_or_create_homer_instance(serial: "HMR-0047", status: "CERTIFIED", homer: homer)

  wo = WorkOrder.find_or_create_by!(part_instance_id: instance.id) do |w|
    w.part_definition = homer
    w.status = "COMPLETE"
  end
  wo.update!(status: "COMPLETE") unless wo.status == "COMPLETE"

  t0 = Time.utc(2026, 5, 20, 9, 0, 0)
  ordered_bom_items.each_with_index do |bom_item, i|
    step = WorkOrderStep.find_or_create_by!(work_order_id: wo.id, bom_item_id: bom_item.id)
    base = t0 + (i * 2).hours
    set_step!(step, {
      status: "CERTIFIED",
      installed_part_instance_id: instance.id,
      installed_actor: INSTALLER,
      installed_at: base,
      validated_actor: VALIDATOR,
      validated_at: base + 30.minutes,
      certified_actor: QA,
      certified_at: base + 1.hour
    })
  end
end

# --- WO-0002: OPEN (mid-build, one blocked step) ---------------------------

SeedHelper.step("WO-0002 (OPEN) — HMR-0006, in progress with a blocked step") do
  instance = find_or_create_homer_instance(serial: "HMR-0006", status: "IN_ASSEMBLY", homer: homer)

  wo = WorkOrder.find_or_create_by!(part_instance_id: instance.id) do |w|
    w.part_definition = homer
    w.status = "OPEN"
  end
  wo.update!(status: "OPEN") unless wo.status == "OPEN"

  t0 = Time.utc(2026, 5, 28, 8, 0, 0)
  # Step plan by BOM position: muzzle installed (4-eyes validated), dome blocked
  # (its muzzle prerequisite is in but stock for the dome is short), engine
  # installed, horn still pending. Demonstrates INSTALLED + BLOCKED + PENDING.
  step_plan = {
    "MUZZLE-001" => :installed_validated,
    "DOME-TRANS-001" => :blocked,
    "ENGINE-V8-001" => :installed,
    "HORN-LCC-001" => :pending
  }

  ordered_bom_items.each_with_index do |bom_item, i|
    step = WorkOrderStep.find_or_create_by!(work_order_id: wo.id, bom_item_id: bom_item.id)
    base = t0 + (i * 1).hours
    attrs =
      case step_plan.fetch(bom_item.child.part_number, :pending)
      when :installed_validated
        {
          status: "VALIDATED",
          installed_part_instance_id: instance.id,
          installed_actor: INSTALLER, installed_at: base,
          validated_actor: VALIDATOR, validated_at: base + 30.minutes,
          certified_actor: nil, certified_at: nil
        }
      when :installed
        {
          status: "INSTALLED",
          installed_part_instance_id: instance.id,
          installed_actor: INSTALLER, installed_at: base,
          validated_actor: nil, validated_at: nil,
          certified_actor: nil, certified_at: nil
        }
      when :blocked
        {
          status: "BLOCKED",
          installed_part_instance_id: nil,
          installed_actor: nil, installed_at: nil,
          validated_actor: nil, validated_at: nil,
          certified_actor: nil, certified_at: nil
        }
      else
        # :pending
        {
          status: "PENDING",
          installed_part_instance_id: nil,
          installed_actor: nil, installed_at: nil,
          validated_actor: nil, validated_at: nil,
          certified_actor: nil, certified_at: nil
        }
      end
    set_step!(step, attrs)
  end
end

# --- WO-0003: BLOCKED (waiting on stock) -----------------------------------

SeedHelper.step("WO-0003 (BLOCKED) — HMR-0007, waiting on stock") do
  instance = find_or_create_homer_instance(serial: "HMR-0007", status: "IN_ASSEMBLY", homer: homer)

  wo = WorkOrder.find_or_create_by!(part_instance_id: instance.id) do |w|
    w.part_definition = homer
    w.status = "BLOCKED"
  end
  wo.update!(status: "BLOCKED") unless wo.status == "BLOCKED"

  # Stock reservation never succeeded: every step is BLOCKED, mirroring what the
  # StockReservationJob would produce when no on-hand stock is available.
  ordered_bom_items.each do |bom_item|
    step = WorkOrderStep.find_or_create_by!(work_order_id: wo.id, bom_item_id: bom_item.id)
    set_step!(step, { status: "BLOCKED" })
  end
end
