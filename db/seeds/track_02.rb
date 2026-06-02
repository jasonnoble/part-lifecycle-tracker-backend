SeedHelper.track("Track 2 — Data Model (JAS-19)")

PART_DEFINITIONS = [
  { part_number: "THE-HOMER-001",  name: "The Homer",              status: "RELEASED", revision: "B", description: "The everyman's car — every feature Homer ever wanted, all at once." },
  { part_number: "HOMER-CLASSIC-001", name: "The Homer (Classic)", status: "OBSOLETE", revision: "A", description: "Superseded by THE-HOMER-001." },
  { part_number: "MARGE-FAM-001",  name: "Marge's Family Cruiser", status: "DRAFT",    revision: nil, description: "Practical, safe family hauler concept." },
  { part_number: "BART-HOT-001",   name: "Bart's Hot Rod",         status: "DRAFT",    revision: nil, description: "High-performance hot rod concept." },
  { part_number: "HORN-LCC-001",   name: "La Cucaracha Horn",      status: "RELEASED", revision: "A", description: "Three-tone horn that plays \"La Cucaracha.\"" },
  { part_number: "DOME-TRANS-001", name: "Transparent Dome",       status: "RELEASED", revision: "A", description: "Clear bubble dome over the passenger compartment." },
  { part_number: "MUZZLE-001",     name: "Muzzle",                 status: "RELEASED", revision: "A", description: "Sound-dampening muzzle; installs before the dome." },
  { part_number: "ENGINE-V8-001",  name: "V8 Engine",              status: "RELEASED", revision: "A", description: "V8 powertrain assembly." }
].freeze

HOMER_BOM = [
  { child: "HORN-LCC-001",   quantity: 3 },
  { child: "DOME-TRANS-001", quantity: 1 },
  { child: "MUZZLE-001",     quantity: 1 },
  { child: "ENGINE-V8-001",  quantity: 1 }
].freeze

# Marge's Family Cruiser is a DRAFT concept with a deliberately *partial* BOM
# (engine + horn only — no dome or muzzle yet), so the UI has a draft-with-a-BOM
# to show and the BOM editor (JAS-71) has something to edit. Children are existing
# RELEASED components.
MARGE_FAM_BOM = [
  { child: "ENGINE-V8-001", quantity: 1 },
  { child: "HORN-LCC-001",  quantity: 1 }
].freeze

SeedHelper.step("seed #{PART_DEFINITIONS.size} part definitions") do
  PartDefinition.upsert_all(PART_DEFINITIONS, unique_by: :part_number)
end

part_definitions = PartDefinition.all.index_by(&:part_number)

SeedHelper.step("seed The Homer BOM") do
  homer = part_definitions.fetch("THE-HOMER-001")
  bom_items = HOMER_BOM.map do |part|
    {
      child_part_definition_id: part_definitions.fetch(part[:child]).id,
      quantity: part[:quantity],
      parent_part_definition_id: homer.id
    }
  end
  BomItem.upsert_all(bom_items, unique_by: [ :parent_part_definition_id, :child_part_definition_id ])
end

SeedHelper.step("seed Marge's Family Cruiser partial BOM (draft part)") do
  marge = part_definitions.fetch("MARGE-FAM-001")
  bom_items = MARGE_FAM_BOM.map do |part|
    {
      child_part_definition_id: part_definitions.fetch(part[:child]).id,
      quantity: part[:quantity],
      parent_part_definition_id: marge.id
    }
  end
  BomItem.upsert_all(bom_items, unique_by: [ :parent_part_definition_id, :child_part_definition_id ])
end

SeedHelper.step("seed muzzle-before-dome dependency") do
  homer  = part_definitions.fetch("THE-HOMER-001")
  muzzle = BomItem.find_by!(parent_part_definition_id: homer.id,
                            child_part_definition_id:  part_definitions.fetch("MUZZLE-001").id)
  dome   = BomItem.find_by!(parent_part_definition_id: homer.id,
                            child_part_definition_id:  part_definitions.fetch("DOME-TRANS-001").id)
  BomItemDependency.upsert_all(
    [
      {
        prerequisite_bom_item_id: muzzle.id,
        dependent_bom_item_id: dome.id
      }
    ],
    unique_by: [ :prerequisite_bom_item_id, :dependent_bom_item_id ]
  )
end

SeedHelper.step("seed stock rows (quantity_on_hand = 0)") do
  rows = part_definitions.values.map do |pd|
    { part_definition_id: pd.id, quantity_on_hand: 0, quantity_reserved: 0 }
  end
  Stock.upsert_all(rows, unique_by: :part_definition_id)
end
