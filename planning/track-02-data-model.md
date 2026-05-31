# Track 2 — Data Model

**Milestone:** Track 2 — Data Model  
**Estimated time:** 4 hours  
**Discussion time:** ~15 minutes

---

## Goal

Get the entire schema in place before any application code. All tables, all constraints, all indexes. Every subsequent track writes application logic against this schema — no schema changes should be needed after Track 2 ships.

---

## Key decisions

**UUIDs across the board** — All primary keys and foreign keys are UUIDs. UUIDs in URLs (no sequential integer IDs exposed externally). `enable_extension 'pgcrypto'` in the first migration, `gen_random_uuid()` as the default.

**BOM dependencies as a join table** — `bom_item_dependencies` with two FK columns (`prerequisite_bom_item_id`, `dependent_bom_item_id`) instead of a single self-referential `required_before_step` FK on BomItem. Reason: assembly steps frequently have multiple prerequisites. Migration cost to change a single-FK design later is high.

**Two timestamps on LifecycleEvent** — `occurred_at` (user-supplied, can be backdated) + `recorded_at` (server-set, always monotonically increasing). They answer different questions: `occurred_at` is for business queries and real-world timing; `recorded_at` enforces append-only audit integrity. No `updated_at` on this table — events are never updated.

**Denormalized `current_status` on PartInstance** — Derive from latest event would require a subquery or join on every list. Denormalized column with a v1 worker to audit for stale values.

**Stock: integer counter + audit log (not event sourced)** — `quantity_on_hand` integer + `StockAuditLog` for changes. Full event sourcing is most valuable for tracking a specific object's history with identity (Part Instances). For fungible inventory counts, a counter + audit log is simpler and sufficient.

**Two-phase stock reservation** — `quantity_on_hand` + `quantity_reserved` on the Stock model. Available = on_hand - reserved. BOM explosion checks available, not on_hand.

**Soft delete on BOM items** — `deleted_at` nullable timestamp. Soft-deleted items remain visible in API responses (UI strikes them through). Hard delete would break historical work order records that reference those BOM items.

---

## Migration integrity checklist

Run this sweep on **every** migration in this track *before* opening the PR — in one pass, not iteratively. These are mostly DB-level constraints; `NOT NULL` alone does not cover them. (Distilled from JAS-11, where they surfaced one at a time across many round trips.)

- **`NOT NULL` ≠ present** — required identifier/text columns (`part_number`, `serial_number`, `name`, `actor`, `reason`, `conducted_by`, `supplier_id`, `customer_name`) also need a non-empty CHECK: `length(trim(col)) > 0`. `NULL` and `''` are different holes.
- **Value ranges** — counts that must be positive get `> 0` (BOM / order-line quantities); balances that can rest at zero get `>= 0` (stock levels, `quantity_received`).
- **Self-reference guards** — any table with two FKs to the same target needs a CHECK that they differ (`parent <> child`, `prerequisite <> dependent`). Catches one-level cycles; multi-level cycles are app logic.
- **Uniqueness × soft delete** — a uniqueness rule on a soft-deletable table must be a *partial* unique index `WHERE deleted_at IS NULL`, or a tombstone blocks re-adding the same key.
- **Status / enum columns** — `string` + CHECK against the valid set (see the status decision in `decisions-a-vs-b.md`), with the spec's default. Not a native PG enum.
- **Append-only tables** — no `updated_at`; `recorded_at` defaults to `now()` at the DB level (`default: -> { "now()" }`).
- **FK `on_delete` intent** — default is `NO ACTION` (restrict). Confirm that's wanted (it usually is here — parts go OBSOLETE, not deleted); pick `:nullify` / `:cascade` deliberately, never by accident.
- **Cross-field invariants** — consider DB CHECKs for `quantity_reserved <= quantity_on_hand`, `quantity_received <= quantity`, etc. Judgment call: enforce at the DB if always true; defer to the app if the domain has exceptions (e.g. over-receipts).
- **Workflow** — never edit an *already-applied* migration and re-run `db:migrate` (it's a no-op; the DB and `schema.rb` silently drift). Re-run with `db:migrate:redo` / `db:migrate:reset`, then re-dump and diff `schema.rb`.

---

## Stories

### Create Part Definition and BOM migrations
**Labels:** data-model, backend  
**What:** Migrations for `part_definitions` and `bom_items`.

`part_definitions` columns:
- `id` uuid PK (gen_random_uuid default)
- `part_number` string unique not null (human-readable, e.g. "THE-HOMER-001")
- `name` string not null
- `description` text
- `revision` string
- `status` string not null default 'DRAFT' (DRAFT / RELEASED / OBSOLETE)
- `created_at`, `updated_at`

`bom_items` columns:
- `id` uuid PK
- `parent_part_definition_id` uuid FK → part_definitions not null
- `child_part_definition_id` uuid FK → part_definitions not null
- `quantity` integer not null
- `deleted_at` timestamp nullable (soft delete)
- `created_at`, `updated_at`

**Acceptance criteria:**
- Both tables use UUID PKs with `gen_random_uuid()` default
- Unique index on `part_definitions.part_number`
- Index on `bom_items.parent_part_definition_id`
- **Partial** unique index on `bom_items (parent_part_definition_id, child_part_definition_id) WHERE deleted_at IS NULL` — at most one *active* line per parent/child pair (quantity expresses multiplicity, not duplicate rows); partial so a soft-deleted line and a re-added one can coexist
- Check constraint `bom_items.quantity > 0` — a BOM line of zero or negative quantity is nonsensical (note: stricter than the `stocks` checks, which are `>= 0`)
- Migrations are reversible

### Create bom_item_dependencies join table migration
**Labels:** data-model, backend  
**What:** Junction table linking BOM items that must be completed before others.

`bom_item_dependencies` columns:
- `id` uuid PK
- `prerequisite_bom_item_id` uuid FK → bom_items not null
- `dependent_bom_item_id` uuid FK → bom_items not null
- `created_at`

**Acceptance criteria:**
- Unique constraint on `(prerequisite_bom_item_id, dependent_bom_item_id)`
- Both FK columns indexed
- Check constraint `prerequisite_bom_item_id <> dependent_bom_item_id` — a BOM item cannot depend on itself (one-level cycle guard; multi-level cycle detection is app logic)
- Migration is reversible

### Create Part Instance and Lifecycle Event migrations
**Labels:** data-model, backend  
**What:** Core event-sourced entities.

`part_instances` columns:
- `id` uuid PK
- `serial_number` string unique not null (e.g. "HMR-0047")
- `part_definition_id` uuid FK → part_definitions not null
- `current_status` string not null (denormalized from latest event) — **no DB default**; set to the first event's type in the creating transaction (unlike `part_definitions.status`, which defaults to `DRAFT` because it isn't event-derived)
- `created_at`, `updated_at` (the instance row **is** mutable — `current_status` is updated as events arrive, unlike the append-only `lifecycle_events` / `test_records`)

`lifecycle_events` columns:
- `id` uuid PK
- `part_instance_id` uuid FK → part_instances not null
- `event_type` string not null (ORDERED / RECEIVED / INSPECTED / IN_ASSEMBLY / INSTALLED / VALIDATED / CERTIFIED)
- `actor` string not null
- `notes` text nullable
- `metadata` jsonb nullable
- `occurred_at` timestamp not null
- `recorded_at` timestamp not null default now()

**Acceptance criteria:**
- `lifecycle_events` has NO `updated_at` column
- `recorded_at` has `default: -> { 'now()' }` at DB level
- Index on `lifecycle_events.part_instance_id`
- Index on `lifecycle_events.occurred_at`
- Non-empty CHECK on `part_instances.serial_number` and `lifecycle_events.actor` (`length(trim(...)) > 0`)
- CHECK `part_instances.current_status` in the lifecycle set (ORDERED / RECEIVED / INSPECTED / IN_ASSEMBLY / INSTALLED / VALIDATED / CERTIFIED)
- CHECK `lifecycle_events.event_type` in the same set

### Create Stock and StockAuditLog migrations
**Labels:** data-model, backend  
**What:** Fungible inventory tracking.

`stocks` columns:
- `id` uuid PK
- `part_definition_id` uuid FK → part_definitions unique not null
- `quantity_on_hand` integer not null default 0
- `quantity_reserved` integer not null default 0
- `created_at`, `updated_at`

`stock_audit_logs` columns:
- `id` uuid PK
- `part_definition_id` uuid FK → part_definitions not null
- `change_amount` integer not null (positive = increase, negative = decrease)
- `reason` string not null
- `recorded_at` timestamp not null default now()

**Acceptance criteria:**
- `stocks` has check constraint: `quantity_on_hand >= 0`, `quantity_reserved >= 0`
- `stock_audit_logs` has NO `updated_at`
- `stock_audit_logs.recorded_at` defaults to `now()` at the DB level
- Unique index on `stocks.part_definition_id`
- Non-empty CHECK on `stock_audit_logs.reason` (`length(trim(reason)) > 0`)
- *Consider* CHECK `quantity_reserved <= quantity_on_hand` (reserved can't exceed on-hand) — adopt if always true; defer to the reservation worker if transient over-reserve states are valid

### Create Customer Order and Customer Order Line migrations
**Labels:** data-model, backend  

`customer_orders` columns:
- `id` uuid PK
- `customer_name` string not null
- `status` string not null default 'OPEN' (OPEN / IN_FULFILLMENT / COMPLETE)
- `created_at`, `updated_at`

`customer_order_lines` columns:
- `id` uuid PK
- `customer_order_id` uuid FK → customer_orders not null
- `part_definition_id` uuid FK → part_definitions not null
- `quantity` integer not null
- `created_at`

**Acceptance criteria:**
- Index on `customer_order_lines.customer_order_id`
- CHECK `customer_orders.status` in (OPEN / IN_FULFILLMENT / COMPLETE)
- Non-empty CHECK on `customer_orders.customer_name`
- Check constraint `customer_order_lines.quantity > 0`

### Create Supplier PO and Supplier PO Line migrations
**Labels:** data-model, backend  

`supplier_purchase_orders` columns:
- `id` uuid PK
- `supplier_id` string not null
- `status` string not null default 'OPEN' (OPEN / PARTIALLY_RECEIVED / RECEIVED / CLOSED)
- `customer_order_id` uuid FK → customer_orders nullable
- `created_at`, `updated_at`

`supplier_purchase_order_lines` columns:
- `id` uuid PK
- `supplier_purchase_order_id` uuid FK → supplier_purchase_orders not null
- `part_definition_id` uuid FK → part_definitions not null
- `quantity` integer not null
- `quantity_received` integer not null default 0
- `status` string not null default 'NEEDS_ORDERING' (NEEDS_ORDERING / ORDERED / PARTIALLY_RECEIVED / RECEIVED)
- `created_at`, `updated_at`

**Acceptance criteria:**
- Per-line status enum enforced at model layer (aasm)
- `customer_order_id` on PO is nullable (system-generated POs may not have a customer order)
- CHECK `supplier_purchase_orders.status` in (OPEN / PARTIALLY_RECEIVED / RECEIVED / CLOSED) and `supplier_purchase_order_lines.status` in (NEEDS_ORDERING / ORDERED / PARTIALLY_RECEIVED / RECEIVED) — DB CHECK complements the aasm model enforcement
- Non-empty CHECK on `supplier_purchase_orders.supplier_id`
- Check constraints `supplier_purchase_order_lines.quantity > 0` and `quantity_received >= 0`
- *Consider* CHECK `quantity_received <= quantity` — defer if over-receipts are allowed in the domain

### Create Work Order and Work Order Step migrations
**Labels:** data-model, backend  

`work_orders` columns:
- `id` uuid PK
- `part_definition_id` uuid FK → part_definitions not null
- `part_instance_id` uuid FK → part_instances not null
- `customer_order_line_id` uuid FK → customer_order_lines nullable
- `status` string not null default 'OPEN' (OPEN / BLOCKED / COMPLETE)
- `created_at`, `updated_at`

`work_order_steps` columns:
- `id` uuid PK
- `work_order_id` uuid FK → work_orders not null
- `bom_item_id` uuid FK → bom_items not null
- `status` string not null default 'PENDING' (PENDING / INSTALLED / VALIDATED / CERTIFIED / BLOCKED)
- `installed_part_instance_id` uuid FK → part_instances nullable
- `installed_actor` string nullable, `installed_at` timestamp nullable
- `validated_actor` string nullable, `validated_at` timestamp nullable
- `certified_actor` string nullable, `certified_at` timestamp nullable
- `created_at`, `updated_at`

**Acceptance criteria:**
- `work_order_steps.status` is denormalized — not derived at query time
- Each of the three assembly phases records **both who and when**: `installed_actor`/`installed_at`, `validated_actor`/`validated_at`, `certified_actor`/`certified_at` — stored separately (the actor columns back 4-eyes; the `*_at` columns give a per-phase audit trail). All nullable; populated as each phase happens. No separate `completed_at` — `certified_at` is the completion timestamp.
- Index on `work_order_steps.work_order_id`
- CHECK `work_orders.status` in (OPEN / BLOCKED / COMPLETE) and `work_order_steps.status` in (PENDING / INSTALLED / VALIDATED / CERTIFIED / BLOCKED)
- DB-level 4-eyes CHECK: `validated_actor IS NULL OR validated_actor <> installed_actor` (belt-and-suspenders for the `SAME_ACTOR` rule the API also enforces — validate must differ from install)
- **Open question (see `decisions.md`):** whether the *certifier* must also be a distinct actor (`certified_actor` ≠ installed/validated) and whether that belongs in a DB CHECK or app-only. Deferred pending a customer conversation; not enforced at the DB in v0 beyond the validate-vs-install rule above.

### Create Test Record migration
**Labels:** data-model, backend  

`test_records` columns:
- `id` uuid PK
- `part_instance_id` uuid FK → part_instances not null
- `test_type` string not null
- `result` string not null (PASS / FAIL / INCONCLUSIVE)
- `notes` text nullable
- `conducted_by` string not null
- `occurred_at` timestamp not null
- `recorded_at` timestamp not null default now()

**Acceptance criteria:**
- No `updated_at` (append-only)
- Index on `test_records.part_instance_id`
- `recorded_at` defaults to `now()` at the DB level
- CHECK `test_records.result` in (PASS / FAIL / INCONCLUSIVE)
- Non-empty CHECK on `test_records.conducted_by` and `test_type` (`length(trim(...)) > 0`)

### Seed Track 2: Part Definitions with BOM
**Labels:** seed-data  
**What:** Idempotent seeds for three part definitions. The Homer is the main demo part.

Part definitions — **7 total** (3 top-level + 4 BOM components; every BOM child must exist as its own `PartDefinition` before its `BomItem` can be created):

| part_number | name | status | description | revision |
|-------------|------|--------|-------------|----------|
| `THE-HOMER-001` | The Homer | RELEASED | The everyman's car — every feature Homer ever wanted, all at once. | B |
| `MARGE-FAM-001` | Marge's Family Cruiser | DRAFT | Practical, safe family hauler concept. | — |
| `BART-HOT-001` | Bart's Hot Rod | DRAFT | High-performance hot rod concept. | — |
| `HORN-LCC-001` | La Cucaracha Horn | RELEASED | Three-tone horn that plays "La Cucaracha." | A |
| `DOME-TRANS-001` | Transparent Dome | RELEASED | Clear bubble dome over the passenger compartment. | A |
| `MUZZLE-001` | Muzzle | RELEASED | Sound-dampening muzzle; installs before the dome. | A |
| `ENGINE-V8-001` | V8 Engine | RELEASED | V8 powertrain assembly. | A |

Components (rows 4–7) are seeded `RELEASED` (real in-production parts) with revision `A`; the DRAFT parts carry no revision (locked/writable only in DRAFT). Descriptions are flavor text (`description` is nullable).

The Homer BOM (at minimum):
- HORN-LCC-001 "La Cucaracha Horn" qty 3
- DOME-TRANS-001 "Transparent Dome" qty 1
- MUZZLE-001 "Muzzle" qty 1  
- ENGINE-V8-001 "V8 Engine" qty 1

BOM dependency: MUZZLE-001 must be INSTALLED before DOME-TRANS-001 (muzzle-before-dome is the canonical test case)

**Models:** the migration stories (JAS-11…18) created schema only — no AR models exist yet. This seed is the *first consumer*, so it brings up the **minimal** model classes it touches: `PartDefinition`, `BomItem`, `BomItemDependency`, `Stock` — bare `ApplicationRecord` subclasses with just the associations needed to seed (parent/child BOM links, the dependency pair, `has_one :stock`). Keep them thin: the `aasm` state machine, validations, scopes, and `Stock#available` land in the API tracks that own each model (Track 3+). Don't add validations that would fight seed insert order (e.g. "RELEASED requires a BOM"). Seeding The Homer as `RELEASED` writes the status column directly, bypassing the future DRAFT→RELEASED transition — expected for seeds.

**Acceptance criteria:**
- Minimal AR models created for `PartDefinition`, `BomItem`, `BomItemDependency`, `Stock` (associations only; enriched in later tracks)
- Seeds are idempotent (safe to re-run, no duplicate rows) — implemented with `upsert_all` keyed on each table's natural unique index (`part_number` for parts; `(parent, child)` for BOM items; `(prerequisite, dependent)` for dependencies; `part_definition_id` for stock). `upsert_all`'s `DO UPDATE` also means edited seed values are picked up on re-run, which `find_or_create_by` would not do.
- At least one `bom_item_dependency` row created
- Stock records created for each part with quantity_on_hand = 0 (will be updated in Track 5 seed)

---

## Blog angles

- "A field that looks like a timestamp is actually two fields pretending to be one." — `occurred_at` vs `recorded_at` on LifecycleEvent.
- "The data model should reflect what manufacturing actually looks like, not what's easiest to scaffold." — BOM dependencies as join table.
- "Knowing when NOT to apply event sourcing is as important as knowing the pattern." — Stock as integer counter.
- The muzzle-before-dome dependency is the canonical test case for the entire app. Name it that early and keep calling it that.
