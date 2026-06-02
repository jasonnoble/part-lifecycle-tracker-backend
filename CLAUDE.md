# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Part Lifecycle Tracker — a Rails 8.1 **API-mode** application (PostgreSQL) tracking aircraft/engine parts from design through manufacture and test. It is a portfolio piece with a 72-hour v0 sprint target. The codebase is early: the full schema (14 domain tables) exists via migrations, but only a few Activerecord models, no controllers, and no routes have been built yet.

### The central domain idea — Definition vs. Instance

Most tools conflate two kinds of knowledge about a "part." This system deliberately splits them, and that split drives the whole data model:

- **Part Definition** (`part_definitions`) — the design artifact. One row per `part_number`. Has a BOM (`bom_items`), stock levels (`stocks`), and a status of `DRAFT`/`RELEASED`/`OBSOLETE`.
- **Part Instance** (`part_instances`) — a physical object with a unique `serial_number`. Many per part number. Its lifecycle is an **append-only event log** (`lifecycle_events`); `current_status` is *derived from the latest event*, never set directly as the source of truth.

When modeling new behavior, keep these two identities separate — they have different lifecycles and answer different questions ("what is this supposed to be?" vs. "where has this specific object been?").

### Settled design decisions (do not relitigate)

1. **Two-entity split** (Definition vs. Instance) above.
2. **Append-only immutable event log** for instances — audit trail and time-series for free; status is always derived.
3. **Hard dependency enforcement** on work order steps — a blocked step must return `409 DEPENDENCY_NOT_MET`, not a warning. The canonical case (seeded) is *muzzle must be installed before the transparent dome*; this requires an explicit integration test.
4. **`/parts/:partNumber/context` endpoint** — returns a rich snapshot meant to drop into an LLM prompt. Its `summary` field is **templated, not LLM-generated** (deterministic and fast).
5. **Rails API mode + PostgreSQL** — chosen for speed of delivery.

### v0 non-goals (do not build)

No auth (one hardcoded API key), no revision-approval workflow, no cost rollup, no MCP server, no where-used endpoint, no websockets, no multi-tenancy.

## Architecture notes

- **UUID primary keys everywhere**, generated in-DB via `gen_random_uuid()` (`pgcrypto` extension, enabled in the first migration). New tables must use `id: :uuid` and `type: :uuid` foreign keys to match.
- **Invariants live in the database, not just the models.** Migrations add `add_check_constraint` for enum-like status fields (`status in (...)`), non-empty strings (`length(trim(...)) > 0`), positive quantities, non-negative stock, no self-references, and a **four-eyes constraint** on `work_order_steps` (`validated_actor <> installed_actor`). When adding states or rules, enforce them at the DB level too — don't rely on model validations alone.
- **Models are intentionally thin so far.** `app/models` has only `part_definition`, `bom_item`, `bom_item_dependency`, `stock`. Associations use explicit `class_name`/`foreign_key` because of the self-referential BOM graph (a `PartDefinition` is both parent and child; a `BomItemDependency` links a prerequisite `BomItem` to a dependent one). Match that explicit style when wiring new associations.
- **Serialization** uses `alba` (+ `oj` for fast JSON); **pagination** uses `pagy`. No jbuilder.
- **Solid* stack** (`solid_queue`, `solid_cache`, `solid_cable`) is DB-backed — these have their own schema files (`db/queue_schema.rb`, etc.); the main app schema is `db/schema.rb`.

## Database / domain map

The schema spans four "tracks":
- **Definition side:** `part_definitions` → `bom_items` (parent/child PartDefinitions + quantity) → `bom_item_dependencies` (prerequisite/dependent BomItems). `stocks` + `stock_audit_logs` track on-hand/reserved quantities.
- **Instance side:** `part_instances` → `lifecycle_events` (append-only; event_type one of ORDERED/RECEIVED/INSPECTED/IN_ASSEMBLY/INSTALLED/VALIDATED/CERTIFIED) and `test_records` (PASS/FAIL/INCONCLUSIVE).
- **Demand:** `customer_orders` → `customer_order_lines`.
- **Supply / build:** `supplier_purchase_orders` → `supplier_purchase_order_lines`; `work_orders` → `work_order_steps` (PENDING/INSTALLED/VALIDATED/CERTIFIED/BLOCKED).

The end-to-end demo flow this must support: create a definition + BOM with a dependency → create & receive a PO (instances appear) → open a work order, get blocked completing the dependent step first, complete the prerequisite, then the dependent → record a test result → complete the work order → call `/context` and get an accurate snapshot.

## Commands

Ruby is managed by **mise** (`.ruby-version` → ruby-4.0.5). Use `mise install` for runtimes, never `brew`.

```bash
bin/setup                  # install deps, prepare DB, start dev (first-time setup)
bin/dev                    # run the app locally
bin/rails db:create db:migrate
bin/rails db:seed          # or: bin/seed — idempotent, upsert-based seeds
bin/rails db:prepare       # create + migrate + seed

bundle exec rspec          # full test suite (real PostgreSQL test DB, no mocking)
bundle exec rspec spec/smoke_spec.rb           # a single file
bundle exec rspec spec/path/to/file_spec.rb:42 # a single example by line

bin/rubocop                # lint (rubocop-rails-omakase house style)
bin/rubocop -a             # autocorrect
bin/brakeman --no-pager    # security scan
bin/bundler-audit          # gem vulnerability scan
```

CI (`.github/workflows/ci.yml`) runs three jobs that must pass: `scan_ruby` (runs `brakeman` then `bundler-audit`), `lint` (`rubocop`), and `rspec` (against a Postgres 13 service). Run `bin/rubocop` and `bundle exec rspec` before pushing.

## Testing conventions

- **RSpec + FactoryBot**, against a **real PostgreSQL** test database (`part_lifecycle_tracker_test`) — the DB layer is never mocked (it's where the invariants live). `rails_helper` calls `maintain_test_schema!`, so run pending migrations before testing.
- `factory_bot` syntax methods are included globally (`create`, `build`, etc.).
- Transactional fixtures are on.
- **Coverage:** SimpleCov runs on every `rspec` (HTML + `coverage/coverage.json`, branch coverage on; `coverage/` is gitignored). The `undercover` gate (`bundle exec undercover --compare <base>`, in `bin/ci` and the CI `rspec` job) fails when new/changed code is uncovered — every PR must cover the code it touches. `SimpleCov.minimum_coverage` in `spec/spec_helper.rb` is a coarse floor (ratchet-up only; never lower it).

## Seeds

`db/seeds.rb` requires every file in `db/seeds/*.rb` in sorted order (`track_01`, `track_02`, …). Seeds are **idempotent** — use `upsert_all` with a `unique_by:` key, the `SeedHelper.step`/`track`/`banner` helpers for output, and `find_or_create_by`-style logic. The seeded `THE-HOMER-001` BOM with its muzzle-before-dome dependency is the reference fixture for the dependency-enforcement demo.

## Workflow

- Issues are tracked in **Linear** (issue keys like `JAS-19` appear in commit messages and seed comments).
- Branch per issue, PR into `main` (see recent git history); CI must be green.
