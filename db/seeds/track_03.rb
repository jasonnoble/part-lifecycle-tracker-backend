SeedHelper.track("Track 3 — Released part with full BOM (JAS-24)")

# Track 3 GUARANTEES the end state Track 4 depends on: THE-HOMER-001 must be a
# RELEASED definition with its full BOM and the muzzle-before-dome dependency in
# place, so part instances can later be built against it.
#
# Track 2 (JAS-19) already seeds all of this. Track 3 is therefore an
# idempotent ENSURING pass: it asserts the required end state and creates only
# what is missing. It must run green whether or not Track 2 ran first, and
# running it repeatedly must never produce duplicate rows.

HOMER_PART_NUMBER = "THE-HOMER-001"

# part_number => quantity for every component The Homer's BOM must contain.
HOMER_REQUIRED_BOM = {
  "HORN-LCC-001"   => 3,
  "DOME-TRANS-001" => 1,
  "MUZZLE-001"     => 1,
  "ENGINE-V8-001"  => 1
}.freeze

# Minimal part-definition attributes used only when a required component is
# missing entirely (e.g. Track 3 runs without Track 2). Kept in sync with Track 2.
HOMER_COMPONENT_DEFINITIONS = {
  HOMER_PART_NUMBER => { name: "The Homer",         status: "RELEASED", revision: "B", description: "The everyman's car — every feature Homer ever wanted, all at once." },
  "HORN-LCC-001"    => { name: "La Cucaracha Horn", status: "RELEASED", revision: "A", description: "Three-tone horn that plays \"La Cucaracha.\"" },
  "DOME-TRANS-001"  => { name: "Transparent Dome",  status: "RELEASED", revision: "A", description: "Clear bubble dome over the passenger compartment." },
  "MUZZLE-001"      => { name: "Muzzle",            status: "RELEASED", revision: "A", description: "Sound-dampening muzzle; installs before the dome." },
  "ENGINE-V8-001"   => { name: "V8 Engine",         status: "RELEASED", revision: "A", description: "V8 powertrain assembly." }
}.freeze

SeedHelper.step("ensure The Homer + components exist as part definitions") do
  rows = HOMER_COMPONENT_DEFINITIONS.map do |part_number, attrs|
    { part_number: part_number, **attrs }
  end
  PartDefinition.upsert_all(rows, unique_by: :part_number)
end

SeedHelper.step("ensure The Homer is RELEASED") do
  homer = PartDefinition.find_by!(part_number: HOMER_PART_NUMBER)
  homer.update!(status: "RELEASED") unless homer.status == "RELEASED"
end

definitions = PartDefinition.where(part_number: HOMER_COMPONENT_DEFINITIONS.keys).index_by(&:part_number)

SeedHelper.step("ensure The Homer's full BOM (#{HOMER_REQUIRED_BOM.size} components)") do
  homer = definitions.fetch(HOMER_PART_NUMBER)
  rows = HOMER_REQUIRED_BOM.map do |child_part_number, quantity|
    {
      parent_part_definition_id: homer.id,
      child_part_definition_id: definitions.fetch(child_part_number).id,
      quantity: quantity
    }
  end
  BomItem.upsert_all(rows, unique_by: [ :parent_part_definition_id, :child_part_definition_id ])
end

SeedHelper.step("ensure muzzle-before-dome dependency") do
  homer  = definitions.fetch(HOMER_PART_NUMBER)
  muzzle = BomItem.find_by!(parent_part_definition_id: homer.id,
                            child_part_definition_id: definitions.fetch("MUZZLE-001").id)
  dome   = BomItem.find_by!(parent_part_definition_id: homer.id,
                            child_part_definition_id: definitions.fetch("DOME-TRANS-001").id)
  BomItemDependency.upsert_all(
    [ { prerequisite_bom_item_id: muzzle.id, dependent_bom_item_id: dome.id } ],
    unique_by: [ :prerequisite_bom_item_id, :dependent_bom_item_id ]
  )
end
