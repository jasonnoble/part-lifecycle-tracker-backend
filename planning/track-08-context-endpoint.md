# Track 8 — /context Endpoint

**Milestone:** Track 8 — /context Endpoint  
**Estimated time:** 2 hours

---

## Goal

A single endpoint that returns a rich, self-contained snapshot of a part's current state — designed to be dropped directly into an LLM prompt. This validates the AI agent use case before the sprint ends and proves the data model is actually useful for downstream consumers.

---

## Key decisions

**Templated summary string, not LLM-generated** — The `summary` field is a pre-written natural language string built from the data. Example: "Family car / sports car hybrid. Rev B released. 400 instances created, 47 in assembly, 12 certified." It is deterministic, fast, and safe to drop into a prompt. An LLM-generated summary would add latency, cost, and non-determinism with no benefit at this scale.

**Single endpoint, all data in one shot** — The endpoint aggregates: part definition, inventory counts by status, open PO count, BOM with stock levels, recent events, generated timestamp. AI agents should be able to answer questions about a part without multiple round-trips.

**Dogfood before shipping** — Before v0 ships, we call the endpoint with real seed data and paste the response into a Claude prompt: "What's the current status of The Homer?" If Claude answers correctly and completely from the single response, the endpoint is working. If it has to ask follow-up questions, the response is missing something.

---

## Stories

### Implement /parts/:id/context endpoint
**Labels:** backend, api  
**What:** `GET /parts/:id/context` — rich snapshot for AI agents.

Response shape:
```json
{
  "partNumber": "THE-HOMER-001",
  "name": "The Homer",
  "revision": "B",
  "status": "RELEASED",
  "summary": "Family car / sports car hybrid. Rev B released. 400 instances created, 47 in assembly, 12 certified.",
  "inventory": {
    "total": 400,
    "byStatus": {
      "RECEIVED": 341,
      "IN_ASSEMBLY": 47,
      "CERTIFIED": 12
    }
  },
  "openPurchaseOrders": 0,
  "bom": [
    {
      "partNumber": "HORN-LCC-001",
      "name": "La Cucaracha horn unit",
      "quantity": 3,
      "stockAvailable": 847
    }
  ],
  "recentEvents": [
    {
      "serialNumber": "HMR-0047",
      "eventType": "IN_ASSEMBLY",
      "occurredAt": "2026-05-28T10:02:00Z",
      "actor": "jamie@factory.com",
      "notes": "WO-0001 opened"
    }
  ],
  "generatedAt": "2026-05-28T09:00:00Z"
}
```

Summary template: `"{name}. Rev {revision} {status_verb}. {total} instances created, {in_assembly} in assembly, {certified} certified."`

**Acceptance criteria:**
- `summary` is templated string, not LLM-generated
- `inventory.byStatus` covers all statuses with at least one instance
- `bom` includes `stockAvailable` (quantity_on_hand - quantity_reserved) for each child part
- `recentEvents` returns last 5 events across all instances, ordered by occurred_at DESC
- `openPurchaseOrders` counts POs in OPEN or PARTIALLY_RECEIVED status
- `generatedAt` reflects server time at response generation
- BOM excludes soft-deleted items
- *Perf watch (don't pre-build — measure first):* `inventory.byStatus` aggregates `part_instances WHERE part_definition_id = X GROUP BY current_status`, which is the higher-cardinality query here (many instances per part). If it's slow at demo scale, add an index on `part_instances (part_definition_id, current_status)`. By contrast the per-instance `lifecycle_events` filters (e.g. by `event_type`) stay tiny — a part instance has only a handful of events — so they don't warrant their own composite index.

### Dogfood /context with a test LLM prompt
**Labels:** test, api  
**What:** Manual test — call /parts/THE-HOMER-001/context with seed data loaded, paste response into a Claude prompt, verify the answer is useful.

Test prompt to use:
```
Here is the current state of part THE-HOMER-001:

[paste /context response]

Questions:
1. How many Homers are currently in assembly?
2. Are there any open purchase orders for this part?
3. What are the components in the Homer's bill of materials?
4. What was the most recent lifecycle event?
```

**Acceptance criteria:**
- Claude answers all 4 questions correctly from the single response
- No "I don't have enough information" responses
- Document the test prompt and response in `docs/context-dogfood-test.md` in the repo

### Write RSpec spec for /context endpoint
**Labels:** test  
**What:** Request spec verifying response shape and data accuracy.

Scenarios:
- Call /context with known seed data, verify inventory counts match actual part_instances
- Verify summary string reflects actual inventory counts
- Verify stockAvailable in BOM matches stock table
- Verify recentEvents ordered correctly
- 404 if part not found

**Acceptance criteria:**
- Real PostgreSQL
- All required fields present
- Counts are accurate (not hardcoded in spec)

### Seed Track 8: Full dataset for /context demo
**Labels:** seed-data  
**What:** Ensure The Homer seed is comprehensive enough for /context to return a meaningful, non-trivial response.

Target state for /context demo:
- Total instances: 15+ with mixed statuses
- At least: 5 RECEIVED, 4 IN_ASSEMBLY, 2 CERTIFIED
- At least 1 open supplier PO showing in openPurchaseOrders
- BOM with stock levels populated

**Acceptance criteria:**
- Summary string has non-zero counts for at least 3 statuses
- /context response is compelling as a demo (not all zeroes)
- Seed is idempotent

---

## Blog angles

- "The summary field is a lie. It looks like AI-generated text. It's a string template." Determinism matters for a system that's meant to power downstream AI queries. You can't debug a response that changes every time.
- The dogfood test is the real acceptance test. "I called the endpoint, pasted the response into Claude, and asked four questions. It got all four right. That's how I knew it was done."
- This endpoint is the bridge between the manufacturing system and the AI agent use case. It's why the data model was designed the way it was — so this one response can answer everything.
