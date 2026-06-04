# Part Lifecycle Tracker — PRD (current)

**Status:** Active — supersedes `part-lifecycle-tracker-prd-v0.md`
**Author:** Jason Noble
**Last updated:** 2026-05-28
**Sources of truth:** Linear project [Part Lifecycle Tracker v0](https://linear.app/jason-noble/project/part-lifecycle-tracker-v0-61dc766d4c8e) (issues JAS-5…JAS-59) and the `planning/` track files. Where this document and the original v0 PRD disagree, this document and Linear win.

> **Why this rewrite exists:** the original v0 PRD was a first-draft spec. The actual design that went into Linear and the `planning/` tracks diverged from it in several material ways — a real Stock model, a demand side (Customer Orders + BOM explosion), UUID keys, a BOM-dependency join table, dual event timestamps, a 4-eyes assembly workflow, and a Rails (not Node) implementation. This PRD describes the system as actually planned and being built.

---

## What this is

A full-stack manufacturing app that tracks a "part" across its entire lifecycle — from a customer placing an order, through supplier purchasing and physical receipt, through assembly with enforced build order and dual sign-off, to a certified finished unit. It is built as a **portfolio piece** and the subject of a "How I Built This" blog series, so the design decisions are first-class artifacts, not just implementation details.

The central design bet: **separate what a part is supposed to be (the Part Definition / design) from what physically exists (the Part Instance / serialized object), and record every change to a physical object as an immutable, append-only event.** That split is what makes questions like "did serial HMR-0047 get the Rev C dome or the Rev B one, and who validated it?" answerable without digging through spreadsheets.

A single `/context` endpoint exposes a rich, self-contained snapshot designed to be dropped straight into an LLM prompt — proving the data model is useful to downstream AI agents.

---

## Problem

Manufacturing tools routinely conflate the design of a part with the physical objects built from it. Once that distinction is lost, you can't trace a specific serial number's revision, build history, or who signed off on each step. v0 proves that separating definitions from instances, tracking instances as append-only events, and enforcing build rules in the system (not in tribal knowledge) makes those questions trivial — and sets up cost rollups, compliance audits, and AI agent queries to work correctly later.

---

## Users & roles

v0 has **no authentication**. The current role is chosen from a header dropdown and persisted in the Rails session. Six named roles drive the UI's role-based actions and the 4-eyes workflow:

| Role | Person (demo) | Does |
|------|---------------|------|
| Salesperson | Sarah Chen | Creates customer orders |
| Floor Manager | Marcus Webb | Oversees assembly floor |
| Tech 1 / Installer | Jamie Torres | Installs parts into a work order step |
| Tech 2 / Validator | Riley Park | Validates that an installation was done correctly |
| QA Engineer | Dr. Quinn | Certifies that a step functionally works |
| Site Manager | Alex Reyes | Cross-cutting oversight |

The **secondary consumer is an AI agent** that calls `GET /parts/:id/context` and answers questions about a part from the single response — validated by a dogfood test before ship.

---

## Core concepts

**The two-entity split (the central decision):**

- **Part Definition** — the design artifact; exists once per part number (e.g. `THE-HOMER-001`). Has a bill of materials (BOM) and a `DRAFT → RELEASED → OBSOLETE` lifecycle.
- **Part Instance** — a physical object with a serial number (e.g. `HMR-0047`); many per part number. Its history is an append-only `LifecycleEvent` log; its `current_status` is derived from the latest event (and denormalized for fast queries).

**The demand-to-fulfillment loop:** Customer Order → (async BOM explosion: reserve stock or raise supplier PO) → Supplier PO received → instances created → Work Order assembles a specific serial through its BOM steps → certified unit.

---

## Data model

All primary and foreign keys are **UUIDs** (`gen_random_uuid()`); UUIDs are used in URLs (no sequential IDs exposed). Migrations are small, focused, and reversible — one table per migration.

### Design side

**`part_definitions`** — `part_number` (unique, human-readable), `name`, `description`, `revision`, `status` (`DRAFT`/`RELEASED`/`OBSOLETE`), timestamps. Revision is writable **only in DRAFT**; once RELEASED, the BOM and revision are locked (change = copy to a new part).

**`bom_items`** — `parent_part_definition_id` FK, `child_part_definition_id` FK (both UUID → `part_definitions`), `quantity`, `deleted_at` (soft delete), timestamps. Soft-deleted items stay visible in API responses (UI strikes them through) so historical work orders that referenced them remain intelligible.

**`bom_item_dependencies`** — join table: `prerequisite_bom_item_id`, `dependent_bom_item_id`, unique on the pair. Modeled as a join table (not a single `required_before_step` FK) because assembly steps often have **multiple** prerequisites. This is the muzzle-before-dome relationship.

### Physical side (event-sourced)

**`part_instances`** — `serial_number` (unique), `part_definition_id` FK (UUID → `part_definitions`), `current_status` (denormalized from latest event), `created_at`, `updated_at` (the row is mutable — `current_status` updates as events arrive).

**`lifecycle_events`** — append-only, **never updated or deleted**, no `updated_at`. `part_instance_id` FK (UUID → `part_instances`), `event_type`, `actor`, `notes`, `metadata` (jsonb), and **two timestamps**: `occurred_at` (client-supplied, can be backdated — real-world timing) and `recorded_at` (server-set `default now()` — audit integrity, monotonic). The client may never set `recorded_at`.

Event sequence: **`RECEIVED → INSPECTED → IN_ASSEMBLY → INSTALLED → VALIDATED → CERTIFIED`.** (`ORDERED` is a PO-line status, not an instance event; instances begin at `RECEIVED`.) `INSTALLED` vs `VALIDATED` vs `CERTIFIED` are deliberately distinct: *was it installed* (installer) vs *was the installation correct* (a second tech) vs *does it functionally work* (QA).

**`test_records`** — append-only, no `updated_at`. `part_instance_id` FK (UUID → `part_instances`), `test_type`, `result` (`PASS`/`FAIL`/`INCONCLUSIVE`), `notes`, `conducted_by`, `occurred_at`, `recorded_at`.

### Inventory (counter + audit log, *not* event-sourced)

**`stocks`** — one per part number: `quantity_on_hand`, `quantity_reserved` (both `>= 0` check constraints). **Available = on_hand − reserved.** Event sourcing is right for identity-bearing instances; for fungible counts a counter plus audit log is simpler and sufficient.

**`stock_audit_logs`** — append-only: `change_amount` (+/−), `reason`, `recorded_at`.

### Demand & supply

**`customer_orders`** / **`customer_order_lines`** — `customer_name`, status (`OPEN`/`IN_FULFILLMENT`/`COMPLETE`); lines have `part_definition_id` FK, `quantity`.

**`supplier_purchase_orders`** / **`supplier_purchase_order_lines`** — `supplier_id`, PO status (`OPEN`/`PARTIALLY_RECEIVED`/`RECEIVED`/`CLOSED`), nullable `customer_order_id`. Per-line status (`NEEDS_ORDERING → ORDERED → PARTIALLY_RECEIVED → RECEIVED`) rolls up to the PO. In v0, **supplier POs are system-generated** by the BOM explosion worker (no warehouse-manager creation UI).

**`work_orders`** / **`work_order_steps`** — a work order targets one part instance (`part_instance_id`) of one part definition (`part_definition_id`), optionally linked to a `customer_order_line_id` for traceability. Status `OPEN`/`BLOCKED`/`COMPLETE`. Each step references a `bom_item_id`, carries denormalized status (`PENDING`/`INSTALLED`/`VALIDATED`/`CERTIFIED`/`BLOCKED`), and records each assembly phase as a separate (`actor`, `at`) pair — `installed_actor`/`installed_at`, `validated_actor`/`validated_at`, `certified_actor`/`certified_at`. The separate actor columns enforce 4-eyes; the `*_at` columns give a per-phase audit trail (`certified_at` is the step's completion time — there is no separate `completed_at`).

---

## API surface

JSON throughout. List endpoints are paginated with **Pagy** (metadata under `meta.pagination`, default 25/page, `?page=` / `?per_page=`). Errors return `{ error, code }`.

**Part Definitions & BOM**
- `GET /parts` (`?status=`, `?search=`), `POST /parts`, `GET /parts/:id` (by UUID *or* part_number), `PATCH /parts/:id` (name/description; revision only if DRAFT)
- `POST /parts/:id/status` — dedicated state-transition endpoint (aasm); not patchable via `PATCH`
- `GET /parts/:id/bom`, `POST /parts/:id/bom` (with `prerequisites`), `DELETE /parts/:id/bom/:bomItemId` (soft)
- `GET /parts/:id/instances`, `GET /parts/:id/context`

**Part Instances**
- `GET /instances` (`?part_number=`, `?status=`), `POST /instances`, `GET /instances/:serial`
- `GET /instances/:serial/events` (ordered `occurred_at` ASC), `POST /instances/:serial/events`
- `GET /instances/:serial/tests`, `POST /instances/:serial/tests`

**Supplier POs**
- `GET /supplier-purchase-orders`, `POST /supplier-purchase-orders`, `GET /supplier-purchase-orders/:id`
- `POST /supplier-purchase-orders/:id/receive` — atomic receive (see below)

**Customer Orders**
- `GET /customer-orders`, `POST /customer-orders` (enqueues BOM explosion), `GET /customer-orders/:id`

**Work Orders**
- `GET /work-orders` (`?status=`), `POST /work-orders` (creates steps from BOM, enqueues stock reservation), `GET /work-orders/:id`
- `POST /work-orders/:id/steps/:stepId/install`, `.../validate`, `.../certify` — three separate endpoints, each with its own guard
- `POST /work-orders/:id/complete` — requires **all steps CERTIFIED**

---

## Key business rules (the logic that matters)

1. **Dependency enforcement → `409 DEPENDENCY_NOT_MET`.** `/steps/:id/install` checks the step's BOM dependencies; if a prerequisite isn't satisfied it returns 409 naming the blocking part. A hard block, not a warning — safety-critical build order belongs in the system. **Canonical test: muzzle-before-dome** (`muzzle_before_dome_spec.rb`), which must pass before ship.
2. **4-eyes → `409 SAME_ACTOR`.** `/validate` rejects the same actor who installed. `installed_actor` and `validated_actor` are stored separately (a DB CHECK also guards `validated_actor <> installed_actor`). `/certify` requires the QA role (`403` otherwise). *(Open: whether the certifier must also differ from the installer/validator — deferred to a customer conversation, see `decisions.md`.)*
3. **Atomic PO receive.** `POST /supplier-purchase-orders/:id/receive` does everything in one DB transaction: validate serials are unique/unused → create instances → append `RECEIVED` events (server-set `recorded_at`) → increment `quantity_on_hand` + write `StockAuditLog` → update line and PO status. Any failure rolls the whole thing back. Duplicate/used serial → `422` before the transaction starts.
4. **Async BOM explosion.** Creating a customer order returns immediately; a Solid Queue worker, per line, checks **available** stock — reserves what's in stock (increments `quantity_reserved`, enqueues work-order creation) and raises supplier PO lines (`NEEDS_ORDERING`) for the shortfall. Atomic per stock row, idempotent.
5. **Two-phase reservation.** Stock checks use available (`on_hand − reserved`), never raw on_hand.
6. **Status transitions are guarded.** DRAFT→RELEASED→OBSOLETE (and DRAFT→OBSOLETE) only; RELEASED→DRAFT and any transition out of OBSOLETE → `422 INVALID_TRANSITION`. Editing revision on a non-DRAFT part → `422 REVISION_LOCKED`.
7. **`/context` summary is templated, never LLM-generated** — deterministic, fast, safe to drop into a prompt. Validated by a dogfood test: paste the response into Claude, ask four questions, all must be answerable from the single response.

Background jobs run on **Solid Queue** (no Redis/Sidekiq): close fully-received POs, reserve stock for new work orders, explode customer-order BOMs.

---

## UI

Five screens, tab navigation (**Assembly Line / Sales / Parts**), role selector in the header. The acceptance bar for the whole UI track: **the demo fails if any step requires explaining what the UI is doing.**

- **Parts List** — searchable table, color-coded status badges, "New Part".
- **Part Detail** — header + status transition controls; BOM as a flat list (soft-deleted struck through); add-BOM-item only when DRAFT; instance count by status; "View /context Response" raw JSON.
- **Work Order** — step list with **role-aware action buttons** (PENDING→Install for techs; INSTALLED→Validate for everyone *except* the installer; VALIDATED→Certify for QA; CERTIFIED→badge only). Blocked steps show the **reason inline** (e.g. "Waiting for Muzzle"). Complete button disabled until all steps CERTIFIED.
- **Instance Detail** — read-only: event log (`occurred_at` ASC, `recorded_at` secondary) + test records (`occurred_at` DESC, color-coded result badges). The event log is the source of truth.
- **Sales / Customer Orders** — visible to Salesperson and Site Manager; list + "New Customer Order"; order detail shows per-line in-stock-vs-needs-ordering.

---

## Tech stack & infrastructure

- **Backend:** Ruby on Rails **8.1**, API-only mode, Ruby 4.0.5. PostgreSQL via `pg`. Serialization with **alba** + **oj**. Pagination with **pagy** (all list endpoints). State machines with **aasm**. OpenAPI docs via **rswag** (served at `/api-docs`).
- **Background jobs / cache / cable:** Solid Queue, Solid Cache, Solid Cable (database-backed; no Redis).
- **Tests:** RSpec + factory_bot against a **real PostgreSQL** test DB — no DB mocking, ever. Integration tests for atomic and business-rule paths.
- **Deploy:** **Kamal 2** to an existing Hetzner CPX21 box (second service alongside jasonnoble.dev) at **`partledger.jasonnoble.dev`**, DNS via Cloudflare, TLS via Let's Encrypt. Puma + Thruster.

---

## Roadmap & status

Work is organized into ten tracks (Linear milestones), each with stories `JAS-5…JAS-59` and an idempotent per-track seed file. Status as of 2026-05-28:

| Track | Scope | Status |
|-------|-------|--------|
| 1 — Infra & Setup | Rails scaffold, RSpec+PG, Pagy, Kamal/Cloudflare deploy, seed foundation | **In progress** — JAS-5/6/7/9 done; JAS-8 (Kamal config), JAS-10 (seed foundation) open |
| 2 — Data Model | All migrations + Track 2 seed | Backlog |
| 3 — Part Definition API | CRUD, status transitions, BOM endpoints | Backlog |
| 4 — Part Instance API | Instances, event log, test records | Backlog |
| 5 — Purchase Orders | Supplier PO endpoints, atomic receive, PO-close worker | Backlog |
| 6 — Work Orders | Creation, install/validate/certify, complete, dependency + stock-reservation logic, muzzle-before-dome test | Backlog |
| 7 — Customer Orders & BOM Explosion | Customer order endpoints, async explosion worker | Backlog (Linear milestone titled "Business Logic") |
| 8 — /context Endpoint | Snapshot endpoint + LLM dogfood | Backlog |
| 9 — UI | Five screens, role selector, tabs | Backlog |
| 10 — Docs & Polish | 5 ADRs, end-to-end demo run, README, rswag, final seed | Backlog |

> Note: the Linear milestone for Track 7 is labeled "Business Logic," but its issues (JAS-41–44) and the `planning/track-07` file both cover **Customer Orders & BOM Explosion**. The dependency-enforcement / 4-eyes business logic lives in Track 6.

---

## Demo acceptance (the real test)

A single person can, with no explanation needed: (1) define a part with a one-dependency BOM, (2) create + receive a supplier PO and watch instances appear, (3) open a work order and see the dependent step blocked, (4) complete the prerequisite then the dependent step (install → validate → certify, with 4-eyes), (5) record a test result, (6) complete the work order, (7) call `/context` and get a response that accurately reflects state. Plus the dogfood test: Claude answers four questions correctly from one `/context` response. Target: clone → demo in under 10 minutes.

---

## Explicit non-goals (v0)

No auth beyond the role dropdown (no passwords/sessions/roles enforcement server-side). No revision-approval workflow / ECOs. No real-time (no websockets/polling/live dashboards). No cost rollups. No MCP server (the `/context` endpoint ships; the MCP wrapper is v1). No where-used / reverse-BOM query. No returned-to-stock event. No multi-tenancy. No warehouse-manager UI for creating supplier POs (system-generated only in v0).

---

## Design decisions (ADRs to write in Track 10)

1. Why Part Definition and Part Instance are separate entities.
2. Why lifecycle events are append-only and never updated.
3. Why supplier PO receive is one atomic endpoint instead of three operations.
4. Why `/context` returns a templated summary string instead of calling an LLM.
5. Why dependency enforcement returns a `409` instead of a warning.
