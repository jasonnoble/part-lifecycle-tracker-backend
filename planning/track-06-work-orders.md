# Track 6 — Work Orders

**Milestone:** Track 6 — Work Orders  
**Estimated time:** 6 hours

---

## Goal

The assembly side of the system. A Work Order is opened against a specific Part Instance and walks through the BOM steps in order. This track ships the dependency enforcement logic — the most important business logic in v0 — plus the 4-eyes installation/validation pattern.

---

## Key decisions

**Dependency enforcement returns 409, not a warning** — `POST /work-orders/:id/steps/:stepId/install` returns `409 DEPENDENCY_NOT_MET` with the blocking part name if prerequisites aren't met. A warning would let technicians skip it, defeating the purpose. Safety-critical assembly order should be encoded in the system, not left to tribal knowledge.

**4-eyes principle on INSTALLED → VALIDATED** — The installer and validator must be different actors. The system enforces this: `POST /steps/:stepId/validate` returns `409 SAME_ACTOR` if the same person who installed is attempting to validate. This is baked into the data model (`installer_actor` and `validator_actor` stored separately) and the API handler.

**Separate endpoints per lifecycle step action** — `/install`, `/validate`, `/certify` are separate endpoints rather than a single `/complete` with a `action` param. Each has its own guard logic and role requirements. Makes the API self-documenting.

**Work order creation is synchronous, stock reservation is async** — Creating a work order returns immediately with steps in PENDING status. A Solid Queue worker then handles stock reservation — incrementing quantity_reserved for each BOM line item if stock is available, or setting the step to BLOCKED if not.

**Denormalized step status** — `work_order_steps.status` is written on each state change, not derived at query time. Querying "all blocked steps" is a simple `WHERE status = 'BLOCKED'`.

**Work order complete requires all steps CERTIFIED** — Not just INSTALLED or VALIDATED. QA sign-off (CERTIFIED) is required for every step before the work order can be closed.

---

## Stories

### Implement Work Order creation endpoint
**Labels:** backend, api  
**What:** `POST /work-orders` — creates a work order + steps from the part's BOM, enqueues stock reservation job.

Body:
```json
{
  "partNumber": "THE-HOMER-001",
  "serialNumber": "HMR-0047",
  "customerOrderLineId": "uuid (optional)"
}
```

Creates:
- One WorkOrder record
- One WorkOrderStep per BOM item on the part definition
- Enqueues StockReservationJob (Solid Queue)

**Acceptance criteria:**
- Work order steps created for each active (non-deleted) BOM item
- Stock reservation job enqueued (not synchronous)
- Response includes work order with steps, each in PENDING status
- 404 if part or serial not found
- 422 if serial already has an open work order

### Implement Work Order step action endpoints
**Labels:** backend, api  
**What:** Three endpoints for step progression:

`POST /work-orders/:id/steps/:stepId/install`
Body: `{ "installedSerial": "HMR-HORN-0391", "actor": "jamie@factory.com" }`
- Checks: step is PENDING, dependency prerequisites met
- Sets `installed_serial`, `installer_actor`, status → INSTALLED
- Appends INSTALLED event to the installed instance

`POST /work-orders/:id/steps/:stepId/validate`
Body: `{ "actor": "riley@factory.com" }`
- Checks: step is INSTALLED, actor ≠ installer_actor
- Sets `validator_actor`, status → VALIDATED

`POST /work-orders/:id/steps/:stepId/certify`
Body: `{ "actor": "quinn@factory.com" }`
- Checks: step is VALIDATED, actor has QA role (session-based in v0)
- Sets status → CERTIFIED

**Acceptance criteria:**
- `/install` returns `409 DEPENDENCY_NOT_MET` with blocking part name if prerequisites unmet
- `/validate` returns `409 SAME_ACTOR` if same person installed
- `/certify` returns `403` if actor doesn't have QA role
- Each action updates step status (denormalized)
- `/install` appends INSTALLED lifecycle event to the installed instance

### Implement Work Order complete endpoint
**Labels:** backend, api  
**What:** `POST /work-orders/:id/complete` — finalizes the work order.

**Acceptance criteria:**
- Returns 422 if any steps are not in CERTIFIED status
- Updates work order status → COMPLETE
- Appends CERTIFIED lifecycle event to the work order's part instance
- Returns completed work order with all steps

### Write RSpec integration test: dependency enforcement (the muzzle-before-dome test)
**Labels:** test  
**What:** The canonical integration test. Must pass before v0 ships.

Scenario:
1. Create The Homer part definition with MUZZLE-001 and DOME-TRANS-001, with muzzle as prerequisite for dome
2. Create instances for both
3. Create a work order for THE-HOMER-001
4. Attempt to install DOME-TRANS-001 first → verify `409 DEPENDENCY_NOT_MET` naming "MUZZLE-001"
5. Install MUZZLE-001 (Tech 1), validate (Tech 2), certify (QA)
6. Now install DOME-TRANS-001 → succeeds
7. Validate and certify DOME-TRANS-001
8. Complete work order → succeeds

**Acceptance criteria:**
- Uses real PostgreSQL
- Covers the full end-to-end sequence
- Tests the same-actor rejection on validate
- Verifies work order status → COMPLETE at the end
- This test is the demo scenario — name it `muzzle_before_dome_spec.rb`

### Implement background worker: stock reservation
**Labels:** worker, backend  
**What:** Solid Queue job triggered by work order creation. For each PENDING step:
- available = quantity_on_hand - quantity_reserved
- If available ≥ 1: increment quantity_reserved, step stays PENDING
- If available < 1: set step status → BLOCKED

**Acceptance criteria:**
- Atomic reservation per step (row-level lock on stocks row)
- Idempotent — re-running doesn't double-reserve
- Blocked steps show up in work order step list with status BLOCKED

### Seed Track 6: Work orders in various states
**Labels:** seed-data  
**What:** Work orders covering the full status range.

Work orders:
- WO-0001: COMPLETE — HMR-0047, all steps certified (the demo completed unit)
- WO-0002: OPEN — HMR-0006, steps in progress (some installed, one blocked)
- WO-0003: BLOCKED — HMR-0007, waiting on stock

**Acceptance criteria:**
- WO-0001 has a full step history with installer_actor, validator_actor, timestamps
- WO-0002 demonstrates the blocked step UI
- Seed is idempotent

---

## Blog angles

- "The dependency check returns a 409, not a warning. Warnings get ignored." This is the central design philosophy: encode safety constraints in the system, not in training materials.
- "The four-eyes check has one line of code: `if installer_actor == actor`. That's it. The hard part was deciding it needed to exist at all."
- The muzzle-before-dome test case: name it early, keep referring to it. It's the demo scenario and the integration test and the blog story all in one.
