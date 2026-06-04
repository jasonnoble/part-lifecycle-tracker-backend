# Part Lifecycle Tracker — Backend

A Rails 8.1 **API-mode** application (PostgreSQL) that tracks a manufactured part
across its entire lifecycle — from a customer order, through supplier purchasing
and physical receipt, through assembly with **enforced build order** and
**dual sign-off**, to a certified finished unit.

- **Live app (React SPA):** <https://app.partledger.jasonnoble.dev/> — one-click demo logins, no signup
- **API + project overview:** <https://partledger.jasonnoble.dev/>
- **User guide (PDF):** [public/user_guide.pdf](public/user_guide.pdf) · [hosted](https://partledger.jasonnoble.dev/user_guide.pdf)
- **API reference (OpenAPI):** [doc/openapi.yaml](doc/openapi.yaml) · [hosted viewer](https://partledger.jasonnoble.dev/docs/)
- **`/context` dogfood test:** [docs/context-dogfood-test.md](docs/context-dogfood-test.md)

## The core idea — Definition vs. Instance

Most tools conflate two kinds of knowledge about a "part." This system splits
them deliberately, and the split drives the whole data model:

- **Part Definition** (`part_definitions`) — the design artifact. One row per
  `part_number`, with a BOM (`bom_items`), stock levels (`stocks`), and a
  `DRAFT`/`RELEASED`/`OBSOLETE` status. Answers *"what is this supposed to be?"*
- **Part Instance** (`part_instances`) — a physical object with a unique
  `serial_number`. Many per part number. Its lifecycle is an **append-only
  event log** (`lifecycle_events`); `current_status` is always *derived from
  the latest event*. Answers *"where has this specific object been?"*

Other settled design decisions:

- **Hard dependency enforcement** on work order steps — installing a step whose
  prerequisite isn't `CERTIFIED` returns `409 DEPENDENCY_NOT_MET`, not a warning.
- **Four-eyes assembly** — the validator must be a *different person* than the
  installer (enforced in the controller, backstopped by a DB `CHECK` constraint).
- **Invariants live in the database** — UUID primary keys, status `CHECK`
  constraints, non-negative stock, no self-referencing BOMs.
- **`GET /parts/:partNumber/context`** — a one-call snapshot designed to drop
  into an LLM prompt; its `summary` is templated, never LLM-generated.

**Stack:** Rails 8.1 (API mode) · PostgreSQL · [Stytch](https://stytch.com)
passwordless auth · alba + oj · pagy · Solid Queue/Cache/Cable · RSpec +
FactoryBot · Kamal 2.

## Local setup

Prerequisites:

- [mise](https://mise.jdx.dev/) (Ruby version per `.ruby-version`)
- PostgreSQL running locally
- `cmake` + `pkg-config` (`brew install cmake pkg-config`) — native deps for the coverage tooling
- `jq` (optional, used by the demo snippets below)
- Credentials — one of:
  - **Maintainer:** the 1Password CLI (`op`). `bin/dev-op` injects
    `RAILS_MASTER_KEY` from 1Password, which unlocks the Stytch credentials in
    `config/credentials.yml.enc`. Bare `bin/rails` commands will fail to
    decrypt credentials — prefix everything with `bin/dev-op`.
  - **Everyone else:** a free [Stytch](https://stytch.com) test project.
    Export `STYTCH_PROJECT_ID` and `STYTCH_SECRET` (env vars take precedence
    over credentials) and generate your own master key.

```bash
git clone git@github.com:jasonnoble/part-lifecycle-tracker.git
cd part-lifecycle-tracker
mise install                                # Ruby
bin/dev-op bin/setup --skip-server          # bundle install + db:prepare (create, migrate, seed)
bin/dev-op bin/rails stytch:sync_users      # link the six seeded demo personas to Stytch (idempotent)
bin/dev-op                                  # boot the API on http://localhost:3000
```

Seeds are **idempotent** (`upsert_all` + `find_or_create_by`) — re-run them any
time with `bin/dev-op bin/seed`. In development, an interactive OpenAPI viewer
is served at `http://localhost:3000/api-docs`.

## Authentication & the six demo personas

Every endpoint except `POST /demo-sessions` and `/up` requires a Stytch session
JWT: `Authorization: Bearer <session_jwt>`. Real users sign in through the SPA
(passwordless magic link / Google); for demos and curl, `POST /demo-sessions`
mints a real Stytch session for one of the **six seeded personas** (the same
endpoint behind the SPA's one-click "Explore as…" logins):

| Persona | Email | Role | Write abilities |
| --- | --- | --- | --- |
| Sarah Chen | `sarah.chen@example.com` | `salesperson` | record lifecycle events |
| Marcus Webb | `marcus.webb@example.com` | `floor_manager` | record lifecycle events |
| Jamie Torres | `jamie.torres@example.com` | `installer` | install + validate steps |
| Riley Park | `riley.park@example.com` | `installer` | install + validate steps (the second pair of eyes) |
| Dr. Quinn | `dr.quinn@example.com` | `qa_engineer` | certify steps, record test results |
| Alex Reyes | `alex.reyes@example.com` | `site_manager` | record lifecycle events |

Any persona can read everything and create parts, BOMs, purchase orders, and
work orders. The role matrix (`app/services/permissions.rb`) gates the assembly
actions: installing/validating is installer work, certification and test
records belong to QA. Four-eyes means the *validator must differ from the
installer* — an identity rule, not a role rule, which is why there are two
installers. An authenticated session with no seeded identity (e.g. your own
Google login) is **read-only**: `GET`s work, writes return `403 READ_ONLY`.

Get a token and check who you are:

```bash
BASE=http://localhost:3000        # or https://partledger.jasonnoble.dev

JAMIE=$(curl -s -X POST "$BASE/demo-sessions" \
  -H 'Content-Type: application/json' \
  -d '{"email":"jamie.torres@example.com"}' | jq -r .session_jwt)

curl -s "$BASE/me" -H "Authorization: Bearer $JAMIE"
# {"email":"jamie.torres@example.com","name":"Jamie Torres","role":"installer",
#  "permissions":["step.install","step.validate","instance.record_event"]}
```

Sessions last 60 minutes. The demo below needs three (installer, second
installer, QA):

```bash
token() {
  curl -s -X POST "$BASE/demo-sessions" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\"}" | jq -r .session_jwt
}
JAMIE=$(token jamie.torres@example.com)   # installer
RILEY=$(token riley.park@example.com)     # installer — the second pair of eyes
QUINN=$(token dr.quinn@example.com)       # qa_engineer
```

## The 7-step demo

The end-to-end flow the system is built around. Each step notes the seeded
records that already demonstrate it, so you can explore without writing
anything.

### 1. A released definition with a BOM dependency

```bash
curl -s "$BASE/parts/THE-HOMER-001" -H "Authorization: Bearer $JAMIE"
curl -s "$BASE/parts/THE-HOMER-001/bom" -H "Authorization: Bearer $JAMIE"
```

The seeded **THE-HOMER-001** ("The Homer", `RELEASED`, Rev B) has a four-item
BOM — 3× `HORN-LCC-001`, 1× `DOME-TRANS-001`, 1× `MUZZLE-001`,
1× `ENGINE-V8-001` — and one dependency: **the muzzle must be certified before
the transparent dome can be installed**.

To build your own instead: `POST /parts` with
`{"part_number": "...", "name": "...", "revision": "A"}`, then
`POST /parts/:partNumber/bom` with
`{"childPartNumber": "...", "quantity": 1, "prerequisites": ["<bomItemId>", ...]}`
(prerequisites are BOM item IDs from earlier calls).

> Seeded by `db/seeds/track_02.rb`/`track_03.rb` — 8 part definitions including
> THE-HOMER-001, its BOM, and the muzzle-before-dome `BomItemDependency`.

### 2. Create a purchase order and receive it — instances appear

Order one of each component, then receive the shipment with explicit serials:

```bash
PO=$(curl -s -X POST "$BASE/supplier-purchase-orders" \
  -H "Authorization: Bearer $JAMIE" -H 'Content-Type: application/json' \
  -d '{
    "supplierId": "VENDOR-DEMO-001",
    "lines": [
      {"partNumber": "MUZZLE-001",     "quantity": 1},
      {"partNumber": "DOME-TRANS-001", "quantity": 1},
      {"partNumber": "ENGINE-V8-001",  "quantity": 1},
      {"partNumber": "HORN-LCC-001",   "quantity": 1}
    ]
  }')
PO_ID=$(echo "$PO" | jq -r .id)

line_id() { echo "$PO" | jq -r ".lines[] | select(.partNumber==\"$1\").id"; }

curl -s -X POST "$BASE/supplier-purchase-orders/$PO_ID/receive" \
  -H "Authorization: Bearer $JAMIE" -H 'Content-Type: application/json' \
  -d "{
    \"lines\": [
      {\"lineId\": \"$(line_id MUZZLE-001)\",     \"quantity\": 1, \"serials\": [\"DEMO-MZL-001\"]},
      {\"lineId\": \"$(line_id DOME-TRANS-001)\", \"quantity\": 1, \"serials\": [\"DEMO-DOME-001\"]},
      {\"lineId\": \"$(line_id ENGINE-V8-001)\",  \"quantity\": 1, \"serials\": [\"DEMO-ENG-001\"]},
      {\"lineId\": \"$(line_id HORN-LCC-001)\",   \"quantity\": 1, \"serials\": [\"DEMO-HORN-001\"]}
    ]
  }"
```

Receiving is **atomic**: in one transaction each serial becomes a
`PartInstance` with an initial `RECEIVED` lifecycle event, stock on-hand
increments (row-locked), a stock audit log is written, and line/PO statuses
roll up. Any failure rolls back the whole shipment.

> Seeded by `db/seeds/track_05.rb` — a `RECEIVED` PO from
> VENDOR-SPRINGFIELD-HORNS-001 that produced 50 horn instances
> (`HORN-LCC-0001`…`0050`), plus an `OPEN` PO awaiting ordering.

### 3. Open a work order; the dependent step is hard-blocked

Create the unit being assembled, open a work order for it (one step per BOM
item), and try the **dome first**:

```bash
curl -s -X POST "$BASE/instances" \
  -H "Authorization: Bearer $JAMIE" -H 'Content-Type: application/json' \
  -d '{"partNumber": "THE-HOMER-001", "serialNumber": "DEMO-HMR-001"}'

WO=$(curl -s -X POST "$BASE/work-orders" \
  -H "Authorization: Bearer $JAMIE" -H 'Content-Type: application/json' \
  -d '{"partNumber": "THE-HOMER-001", "serialNumber": "DEMO-HMR-001"}')
WO_ID=$(echo "$WO" | jq -r .id)

step_id() { echo "$WO" | jq -r ".steps[] | select(.childPartNumber==\"$1\").id"; }

curl -si -X POST "$BASE/work-orders/$WO_ID/steps/$(step_id DOME-TRANS-001)/install" \
  -H "Authorization: Bearer $JAMIE" -H 'Content-Type: application/json' \
  -d '{"installedSerial": "DEMO-DOME-001"}'
# HTTP/1.1 409 Conflict
# {"error":"Prerequisite MUZZLE-001 must be CERTIFIED before this step can be installed",
#  "code":"DEPENDENCY_NOT_MET"}
```

> Seeded by `db/seeds/track_06.rb` — three work orders against THE-HOMER-001:
> **WO-0001** (`HMR-0047`, `COMPLETE`, full four-eyes history), **WO-0002**
> (`HMR-0006`, `OPEN`, mid-build with the dome step `BLOCKED` on exactly this
> rule), and **WO-0003** (`HMR-0007`, `BLOCKED` waiting on stock).

### 4. Complete the prerequisite, then the dependent step

Each step walks install → validate → certify, with three different people:

```bash
# Muzzle: install (Jamie) → validate (Riley) → certify (Dr. Quinn)
curl -s -X POST "$BASE/work-orders/$WO_ID/steps/$(step_id MUZZLE-001)/install" \
  -H "Authorization: Bearer $JAMIE" -H 'Content-Type: application/json' \
  -d '{"installedSerial": "DEMO-MZL-001"}'
curl -s -X POST "$BASE/work-orders/$WO_ID/steps/$(step_id MUZZLE-001)/validate" \
  -H "Authorization: Bearer $RILEY"
curl -s -X POST "$BASE/work-orders/$WO_ID/steps/$(step_id MUZZLE-001)/certify" \
  -H "Authorization: Bearer $QUINN"

# Now the dome goes through — same dance:
curl -s -X POST "$BASE/work-orders/$WO_ID/steps/$(step_id DOME-TRANS-001)/install" \
  -H "Authorization: Bearer $JAMIE" -H 'Content-Type: application/json' \
  -d '{"installedSerial": "DEMO-DOME-001"}'
curl -s -X POST "$BASE/work-orders/$WO_ID/steps/$(step_id DOME-TRANS-001)/validate" \
  -H "Authorization: Bearer $RILEY"
curl -s -X POST "$BASE/work-orders/$WO_ID/steps/$(step_id DOME-TRANS-001)/certify" \
  -H "Authorization: Bearer $QUINN"
```

Repeat install → validate → certify for the engine (`DEMO-ENG-001`) and horn
(`DEMO-HORN-001`) steps. Two enforcement rules worth trying on purpose:

- Validate with `$JAMIE` (the installer) → `409 SAME_ACTOR` — four-eyes.
- Certify with `$JAMIE` (an installer) → `403 FORBIDDEN` — QA's job.

### 5. Record a test result

```bash
curl -s -X POST "$BASE/instances/DEMO-HMR-001/tests" \
  -H "Authorization: Bearer $QUINN" -H 'Content-Type: application/json' \
  -d '{
    "testType": "FINAL_QA",
    "result": "PASS",
    "notes": "All systems nominal",
    "occurredAt": "2026-06-04T15:30:00Z"
  }'
```

Results are `PASS` / `FAIL` / `INCONCLUSIVE`; only `qa_engineer` may record them.
`occurredAt` (when the test physically happened) is required and may differ
from `recordedAt`, which the API stamps itself.

> Seeded by `db/seeds/track_08.rb` — `HMR-0016` (a certified unit) carries a
> full QA history: HORN_SEQUENCE `FAIL` → `PASS` on retest, DOME_PRESSURE
> `PASS`, EMISSIONS `INCONCLUSIVE`, FINAL_QA `PASS`.

### 6. Complete the work order

```bash
curl -s -X POST "$BASE/work-orders/$WO_ID/complete" -H "Authorization: Bearer $QUINN"
```

The gate: **every step must be `CERTIFIED`**. On success the work order
transitions to `COMPLETE` and a `CERTIFIED` lifecycle event is appended to the
assembled unit — `DEMO-HMR-001`'s `current_status` becomes `CERTIFIED`, derived
from its event log like every other status change.

### 7. Call `/context` and verify the snapshot

```bash
curl -s "$BASE/parts/THE-HOMER-001/context" -H "Authorization: Bearer $QUINN"
```

One self-contained response: inventory counts by status, open purchase orders,
the BOM with available stock per child, the five most recent lifecycle events,
and a `summary` string built from a fixed template (deterministic — **not**
LLM-generated), e.g.
`"The Homer. Rev B released. 24 instances created, 9 in assembly, 4 certified."`
Your `DEMO-HMR-001` shows up in the totals, the certified count, and the
recent events.

This endpoint exists so an AI agent can answer questions about a part from a
single call — see the dogfood writeup that validates exactly that:
[docs/context-dogfood-test.md](docs/context-dogfood-test.md).

## The seeded demo dataset

`bin/seed` (→ `bin/rails db:seed`) loads `db/seeds/track_*.rb` in order. Every
track is idempotent — safe to re-run after experimenting.

| Track | Seeds |
| --- | --- |
| `track_01` | Seeding harness smoke check — no domain data. |
| `track_02` | 8 part definitions (THE-HOMER-001 `RELEASED`, HOMER-CLASSIC-001 `OBSOLETE`, MARGE-FAM-001 + BART-HOT-001 `DRAFT`, four released components), the Homer BOM, and the **muzzle-before-dome dependency**. |
| `track_03` | Ensure-state pass: guarantees THE-HOMER-001 is released with its full BOM + dependency, creating only what's missing. |
| `track_05` | Supply side: one `OPEN` PO (10× MARGE-FAM-001) and one `RECEIVED` PO whose receipt produced 50 horn instances (`HORN-LCC-0001`…`0050`) with `RECEIVED` events, stock 50 on-hand, and an audit log. |
| `track_06` | The **six demo personas** (see table above) and three work orders in three states: WO-0001 `COMPLETE` (`HMR-0047`), WO-0002 `OPEN` with a blocked dome step (`HMR-0006`), WO-0003 `BLOCKED` on stock (`HMR-0007`). |
| `track_07` | Demand side: CO-0001 "Powell Motors" (5× Homer, fully reserved, instances + work orders created) and CO-0002 "Springfield Taxi Co" (20× Homer, partial stock — the 10-unit shortfall becomes a supplier PO). |
| `track_08` | The `/context` showcase: 15 Homer instances (`HMR-0001`…`HMR-0017`) spread across every lifecycle status, full append-only event chains, component stock levels, the `HMR-0016` test history, and an `OPEN` 25-unit PO. |
| `track_09` | No-empty-states pass: two more customer orders ("Kwik-E-Mart" `OPEN`, "Springfield Monorail Co" `COMPLETE`). |

## Tests, lint, CI

```bash
bundle exec rspec            # full suite — real PostgreSQL test DB, no mocking
bin/rubocop                  # lint (rubocop-rails-omakase)
bin/brakeman --no-pager      # static security scan
bin/bundler-audit            # gem vulnerability scan
bin/ci                       # everything CI runs, locally — green here means green CI
```

The DB layer is never mocked — the invariants live there, so tests run against
a real `part_lifecycle_tracker_test` database. The OpenAPI spec is generated
from request specs (`OPENAPI=1 bundle exec rspec`); `bin/ci` fails if
`doc/openapi.yaml` is stale.

### Code coverage

Test coverage is measured by [SimpleCov](https://github.com/simplecov-ruby/simplecov)
and gated per-PR by [undercover](https://github.com/grodowski/undercover).

* Running `bundle exec rspec` writes a browsable HTML report to `coverage/index.html`
  and `coverage/coverage.json` (consumed by undercover). Branch coverage is enabled.
  `coverage/` is gitignored — no baseline file is committed.
* **Diff gate:** every PR must keep new or changed Ruby code covered. The undercover
  step (`bundle exec undercover --compare <base>`) fails the build when changed
  blocks lack a test. This enforces "a merge can only keep coverage the same or
  raise it" by construction, without persisting a baseline percentage.
* **Floor:** `SimpleCov.minimum_coverage` in `spec/spec_helper.rb` is a coarse
  safety floor (line 75% / branch 90%) — deliberately set a few points below the
  measured baseline (line ~80% / branch 95%) so it's a safety net, not a tripwire;
  the `undercover` diff gate does the real per-PR enforcement. It is
  **ratchet-up only** — raise it as coverage improves; never lower it.

Native build note: undercover depends on `rugged`, whose native extension needs
`cmake` and `pkg-config` (`brew install cmake pkg-config` on macOS).

## Deployment

Deployed with [Kamal 2](https://kamal-deploy.org) (`config/deploy.yml`): the
image builds to GHCR and runs on a Hetzner host behind kamal-proxy with
Let's Encrypt + Cloudflare at `partledger.jasonnoble.dev`. Secrets
(`RAILS_MASTER_KEY`, `DATABASE_URL`, `STYTCH_PROJECT_ID`, `STYTCH_SECRET`) are
resolved at deploy time from 1Password via `.kamal/secrets` — nothing sensitive
lives in the repo.

```bash
kamal deploy
```
