# Track 5 — Purchase Orders

**Milestone:** Track 5 — Purchase Orders  
**Estimated time:** 4 hours

---

## Goal

The supply side of the demand-to-fulfillment chain. A Supplier PO represents an order placed with a vendor. Receiving it creates Part Instances, updates stock, and kicks off downstream work. This track also ships the background worker that closes completed POs.

---

## Key decisions

**PO receive is one atomic endpoint** — `POST /supplier-purchase-orders/:id/receive` does everything in a single DB transaction: marks lines received, creates instances with serial numbers, appends RECEIVED events, updates stock quantity_on_hand. If anything fails, the whole thing rolls back. This matches how real receiving works — you either receive a shipment or you don't.

**v0 POs are system-generated only** — No warehouse manager UI for creating POs in v0. The BOM explosion worker creates supplier PO lines with NEEDS_ORDERING status. A warehouse manager UI is a v1 enhancement.

**Per-line status** — Each PO line has its own status: NEEDS_ORDERING → ORDERED → PARTIALLY_RECEIVED → RECEIVED. The PO-level status rolls up from line statuses: all lines RECEIVED = PO RECEIVED.

**Background worker closes completed POs** — A Solid Queue worker finds POs where all lines are RECEIVED, marks the PO CLOSED, and triggers work order creation for any associated customer order lines. No Redis, no Sidekiq — Solid Queue uses the existing database.

**Serials assigned at receive time** — The client submits an array of serial numbers when receiving. This matches real practice: the factory assigns serial numbers when parts arrive, not when they're ordered.

---

## Stories

### Implement Supplier PO endpoints
**Labels:** backend, api  
**What:** `GET /supplier-purchase-orders`, `POST /supplier-purchase-orders`, `GET /supplier-purchase-orders/:id`

POST body:
```json
{
  "supplierId": "VENDOR-ACME-001",
  "lines": [
    { "partNumber": "HORN-LCC-001", "quantity": 50 }
  ]
}
```

**Acceptance criteria:**
- PO created with at least one line item (validation)
- Response includes lines with per-line status
- List paginated with Pagy
- GET by ID includes lines with part details

### Implement PO receive endpoint
**Labels:** backend, api  
**What:** `POST /supplier-purchase-orders/:id/receive` — atomic receive operation.

Request body:
```json
{
  "lines": [
    {
      "lineId": "uuid",
      "quantity": 10,
      "serials": ["HMR-0001", "HMR-0002", "..."]
    }
  ]
}
```

In a single transaction:
1. Validate all serial numbers are unique and not already in use
2. Create PartInstance for each serial
3. Append RECEIVED lifecycle event to each instance (actor = "system/receive", recorded_at = now())
4. Increment `stocks.quantity_on_hand` for each part_number
5. Create StockAuditLog entry
6. Update PO line status → RECEIVED (or PARTIALLY_RECEIVED if quantity < ordered)
7. Update PO status → RECEIVED or PARTIALLY_RECEIVED

**Acceptance criteria:**
- Entire operation is one DB transaction — any failure rolls back everything
- Each received serial gets a RECEIVED event with server-set recorded_at
- `stocks.quantity_on_hand` incremented correctly
- Duplicate serial returns 422 before transaction begins
- PO line and PO status updated correctly
- Returns 404 if PO not found

### Implement background worker: close completed Supplier POs
**Labels:** worker, backend  
**What:** Solid Queue job that finds Supplier POs where all lines are RECEIVED, marks PO as CLOSED.

**Acceptance criteria:**
- Runs via Solid Queue (no Sidekiq or Redis)
- Idempotent — safe to run multiple times
- Only processes POs in RECEIVED status (not already CLOSED)
- Logs completion

### Write RSpec specs for PO receive
**Labels:** test  
**What:** Integration test for the atomic receive endpoint.

Key scenarios:
- Receive all lines on a PO — verify instances created, events appended, stock updated, PO status = RECEIVED
- Receive partial quantity — verify PO status = PARTIALLY_RECEIVED
- Submit duplicate serial in same request — verify 422, no instances created
- Submit already-used serial — verify 422, rollback

**Acceptance criteria:**
- Real PostgreSQL
- Verify stock.quantity_on_hand atomically updated
- Verify rollback: if any serial fails, no instances created and stock unchanged

### Seed Track 5: Supplier POs and received instances
**Labels:** seed-data  
**What:** One open Supplier PO (MARGE-FAM-001 parts, awaiting receipt) and one received PO (La Cucaracha Horns for The Homer, already received).

**Acceptance criteria:**
- Received PO has instances in part_instances (HORN-LCC-0001 through HORN-LCC-0050)
- stock.quantity_on_hand = 50 for HORN-LCC-001 after seed
- Open PO shows NEEDS_ORDERING status on lines
- Seed is idempotent

---

## Blog angles

- "The receive endpoint does five things, and that's by design." Atomicity isn't a nice-to-have when you're tracking physical objects — partial state is worse than no state.
- Solid Queue in Rails 8: "zero-infrastructure background jobs — no Sidekiq, no Redis, just the database you already have." This matters for a 72-hour sprint.
