# Track 7 — Customer Orders & BOM Explosion

**Milestone:** Track 7 — Customer Orders & BOM Explosion  
**Estimated time:** 4 hours

---

## Goal

The demand side of the supply chain. A salesperson creates a Customer Order. The system asynchronously explodes the BOM — checking stock, reserving what's available, and creating supplier PO lines for what isn't. This is where the full demand-to-fulfillment loop closes.

---

## Key decisions

**BOM explosion is async** — Creating a customer order returns immediately. A Solid Queue worker handles stock checking and downstream creation. Synchronous BOM explosion blocks on complex BOMs and doesn't reflect how real manufacturing systems work.

**Two-path BOM explosion** — For each customer order line:
- In stock: increment `quantity_reserved`, enqueue work order creation
- Out of stock: create a supplier PO line with status NEEDS_ORDERING

**Salesperson creates customer orders via UI** — In v0, the salesperson role sees a "New Customer Order" button. The order is general (any part definition), not hardcoded to The Homer.

**Stock check uses available quantity** — available = quantity_on_hand - quantity_reserved. Not just on_hand. A unit that's reserved for another order isn't available.

**Customer order links to work orders** — When a work order is created from a customer order, `work_orders.customer_order_line_id` is set. This provides traceability: you can see which customer order a specific assembly is fulfilling.

---

## Stories

### Implement Customer Order endpoints
**Labels:** backend, api  
**What:** `GET /customer-orders`, `POST /customer-orders`, `GET /customer-orders/:id`

POST body:
```json
{
  "customerName": "Powell Motors",
  "lines": [
    { "partNumber": "THE-HOMER-001", "quantity": 5 }
  ]
}
```

Creating a customer order enqueues a BomExplosionJob for each line.

**Acceptance criteria:**
- Customer order created with lines
- BOM explosion job enqueued (Solid Queue)
- Response includes order with lines and initial status OPEN
- List paginated with Pagy

### Implement BOM explosion worker
**Labels:** worker, backend  
**What:** Solid Queue job — for each customer order line:
1. Calculate available = quantity_on_hand - quantity_reserved
2. If available ≥ quantity ordered:
   - Increment quantity_reserved
   - Create StockAuditLog entry
   - Enqueue WorkOrderCreationJob (or create work order synchronously)
3. If available < quantity:
   - Create supplier PO or add line to existing open PO with NEEDS_ORDERING status

**Acceptance criteria:**
- Stock check + reservation is atomic (row-level lock)
- In-stock: quantity_reserved incremented, work order creation triggered
- Out-of-stock: supplier PO line created with NEEDS_ORDERING
- Idempotent — re-running doesn't create duplicate PO lines or double-reserve
- Customer order status updated to IN_FULFILLMENT once explosion completes

### Write RSpec specs for BOM explosion
**Labels:** test  
**What:** Integration tests for both explosion paths.

Scenarios:
- In-stock: create customer order with stock available → verify reservation incremented, work order created
- Out-of-stock: create customer order with no stock → verify supplier PO line created with NEEDS_ORDERING
- Partial stock: order qty 5, stock qty 3 → verify reservation for 3, PO line for 2

**Acceptance criteria:**
- Real PostgreSQL
- Verify quantity_reserved incremented atomically
- Verify supplier PO line only created for out-of-stock quantity
- No double-creation on re-run

### Seed Track 7: Customer orders and BOM explosion results
**Labels:** seed-data  
**What:** Customer orders in different fulfillment states.

Orders:
- CO-0001: "Powell Motors" — 5x THE-HOMER-001, fully in-stock, work orders created
- CO-0002: "Springfield Taxi Co" — 20x THE-HOMER-001, partially in-stock (10 reserved, 10 need ordering)

**Acceptance criteria:**
- CO-0001 has work orders linked via customer_order_line_id
- CO-0002 has a supplier PO with NEEDS_ORDERING lines
- Stock shows correct quantity_reserved after seed
- Seed is idempotent

---

## Blog angles

- "When Powell Motors orders 5 Homers, the system doesn't make them wait for a stock check. It takes the order, returns success, and figures out fulfillment in the background." Async BOM explosion is the right model for a manufacturing system.
- "Solid Queue in Rails 8: no Sidekiq, no Redis. The database you're already running handles the job queue." This matters for demo reliability — one fewer service to be down.
