SeedHelper.track("Track 9 — UI-ready seed data: no empty states (JAS-54)")

# Final "no empty states" pass. Runs last (sorted filename), so every part
# definition, instance, and certified unit the earlier tracks build already
# exists. It fills the remaining UI gaps that aren't owned by a definition-side
# (track_02) or instance-side (track_08) track:
#
#   * Customer orders in the OPEN and COMPLETE fulfillment states. Track 7 only
#     seeds IN_FULFILLMENT orders (Powell, Springfield), so without these two the
#     customer-orders list can't show every state.
#
# Already covered elsewhere (left alone here to avoid double-seeding):
#   * OBSOLETE part + a DRAFT part with a partial BOM  -> track_02 (JAS-54)
#   * work orders in every status (OPEN/BLOCKED/COMPLETE) -> track_06
#   * a certified instance with a full event history    -> track_08
#   * TestRecords incl. a FAIL on a certified instance   -> track_08 (JAS-74)
#
# Each customer order is built directly at its target end state and is idempotent
# (find_or_create_by! on customer_name, reconcile status/quantity). These two are
# seeded WITHOUT touching stock: the OPEN order is pre-explosion (nothing reserved
# yet) and the COMPLETE order is historical demand shown at its end state, so
# neither disturbs Track 7's reserved == on_hand stock invariant.

HOMER = PartDefinition.find_by!(part_number: "THE-HOMER-001")

# customer_name => { status:, quantity: } for the two missing fulfillment states.
UI_CUSTOMER_ORDERS = {
  "Kwik-E-Mart"           => { status: "OPEN",     quantity: 3 },  # just placed, not yet in fulfillment
  "Springfield Monorail Co" => { status: "COMPLETE", quantity: 1 } # fully fulfilled and closed
}.freeze

UI_CUSTOMER_ORDERS.each do |customer_name, attrs|
  SeedHelper.step("#{customer_name} customer order — #{attrs[:quantity]}x THE-HOMER-001 (#{attrs[:status]})") do
    order = CustomerOrder.find_or_create_by!(customer_name: customer_name) do |co|
      co.status = attrs[:status]
    end
    order.update!(status: attrs[:status]) unless order.status == attrs[:status]

    line = CustomerOrderLine.find_or_create_by!(customer_order_id: order.id,
                                                part_definition_id: HOMER.id) do |l|
      l.quantity = attrs[:quantity]
    end
    line.update!(quantity: attrs[:quantity]) unless line.quantity == attrs[:quantity]
  end
end
