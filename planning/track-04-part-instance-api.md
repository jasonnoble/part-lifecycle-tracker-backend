# Track 4 — Part Instance API

**Milestone:** Track 4 — Part Instance API  
**Estimated time:** 4 hours  
**Discussion time:** ~25 minutes

---

## Goal

The "physical object" half of the two-entity split. Every Part Instance has a serial number and an immutable append-only event log. This track ships the API to create instances, record events against them, and query their history.

---

## Key decisions

**Event sequence: ORDERED → RECEIVED → INSPECTED → IN_ASSEMBLY → INSTALLED → VALIDATED → CERTIFIED**
- ORDERED removed from instance sequence in v0 — it's a PO line status, not an instance event. Instances begin at RECEIVED (when they're physically received and assigned a serial).
- INSTALLED = Tech 1 physically installs the part in the assembly
- VALIDATED = Tech 2 (different person) confirms installation was correct — four-eyes principle baked into the model
- CERTIFIED = QA engineer verifies functional requirements (does the turn signal actually blink?)

**INSTALLED vs VALIDATED distinction** — These are different questions asked by different people. "Was it installed?" (installer) vs "Was the installation correct?" (second tech). Separate events make this unambiguous.

**VALIDATED vs CERTIFIED distinction** — Installation correctness vs functional correctness. A turn signal that's correctly installed might still not blink. QA's job is to answer a different question than the validator's.

**occurred_at user-supplied, recorded_at server-set** — An event might be recorded after it occurred (backfill, late data entry). `occurred_at` reflects the real-world time; `recorded_at` is when the row was written. Never allow client to set `recorded_at`.

**Denormalized current_status** — Updated by the event append handler. Not derived at query time via MAX/subquery. A v1 audit worker will detect stale values.

**Returned-to-stock is a v1 feature** — Not in this event sequence for v0. Captured in v1 backlog.

---

## Stories

### Implement Part Instance endpoints
**Labels:** backend, api  
**What:** Core instance CRUD and event log endpoints.

Endpoints:
- `GET /instances` — list, paginated, supports `?part_number=` and `?status=`
- `POST /instances` — manual create (supply part_number, serial_number)
- `GET /instances/:serial` — fetch instance + current_status
- `GET /instances/:serial/events` — ordered event log (occurred_at ASC)
- `POST /instances/:serial/events` — append a lifecycle event

POST /instances/:serial/events body:
```json
{
  "eventType": "RECEIVED",
  "actor": "tech@factory.com",
  "notes": "Visual inspection passed",
  "occurredAt": "2026-05-28T10:00:00Z",
  "metadata": {}
}
```

**Acceptance criteria:**
- `recorded_at` always set server-side (never accepted from client)
- `occurred_at` must be provided by client
- Appending an event updates `current_status` on the part_instance record
- `GET /instances/:serial/events` ordered **deterministically** by `(occurred_at ASC, id)` — `occurred_at` alone is neither unique nor monotonic (backdated events, ties), so it needs a tiebreaker for stable Pagy page boundaries; the `(part_instance_id, occurred_at)` index covers the leading columns
- Returns 404 if serial not found

### Implement Test Record endpoints
**Labels:** backend, api  
**What:** `GET /instances/:serial/tests` and `POST /instances/:serial/tests`

POST body:
```json
{
  "testType": "HORN_SEQUENCE",
  "result": "PASS",
  "notes": "All 7 bars played",
  "conductedBy": "qa@factory.com",
  "occurredAt": "2026-05-28T14:00:00Z"
}
```

**Acceptance criteria:**
- Returns 404 if serial not found
- `result` enum enforced: PASS / FAIL / INCONCLUSIVE
- List ordered by `occurred_at` DESC
- No `updatedAt` in response (append-only)

### Implement /parts/:id/instances endpoint
**Labels:** backend, api  
**What:** `GET /parts/:id/instances` — list all instances for a given part number.

**Acceptance criteria:**
- Returns 404 if part not found
- Supports `?status=` filter
- Paginated with Pagy

### Write RSpec request specs for Part Instance and Test Record APIs
**Labels:** test  
**What:** Request specs covering instance creation, event appending, and test recording.

Key scenarios:
- Create instance, append RECEIVED event, verify current_status updated
- Append events in occurred_at order, verify event log order
- Attempt to set recorded_at from client — verify it's ignored
- Record PASS test, list tests, verify order
- Invalid event type → 422
- Invalid test result → 422

**Acceptance criteria:**
- Real PostgreSQL, no mocks
- Verify both occurred_at and recorded_at set correctly on event create
- Verify current_status on part_instance after each event append

### Seed Track 4: Part Instances and events
**Labels:** seed-data  
**What:** Create ~10 Homer instances with varied lifecycle histories.

Instances:
- HMR-0001 through HMR-0005: RECEIVED
- HMR-0006, HMR-0007: IN_ASSEMBLY
- HMR-0008: INSTALLED (one step done)
- HMR-0009: VALIDATED
- HMR-0047: Full history — RECEIVED → IN_ASSEMBLY → INSTALLED → VALIDATED → CERTIFIED (the demo unit)

**Acceptance criteria:**
- At least one instance with a complete lifecycle history
- HMR-0047 has events for every step in the sequence
- Stock quantity_on_hand updated to reflect received instances
- Seed is idempotent

---

## Blog angles

- "The event sequence isn't arbitrary — it encodes a real manufacturing QA pattern." Four-eyes principle baked into the data model, not tribal knowledge.
- "INSTALLED and VALIDATED sound like the same thing. They're not." Installation correctness (did you put it in right?) vs. functional correctness (does it work?) are different questions, asked by different people, at different points in the process.
- Separating occurred_at from recorded_at: "A field that looks like one timestamp is actually two fields pretending to be one."
