# Dogfooding the `/context` endpoint

## What this endpoint is for

`GET /parts/:partNumber/context` returns a single, self-contained snapshot of a
part's current state — designed to be dropped straight into an LLM prompt. One
response is meant to answer "what is this part, how many exist and in what
state, what's on order, what's in the BOM, and what just happened?" without any
follow-up round-trips to the API.

The `summary` field **is a deterministic, templated string — not
LLM-generated**. It is built from the same aggregate data the rest of the
response carries, using a fixed template
(`"{name}. Rev {revision} {status_verb}. {total} instances created, {in_assembly} in assembly, {certified} certified."`).
That keeps the response fast, free, reproducible, and safe to cache or diff. An
LLM-generated summary would add latency, cost, and non-determinism with no
benefit at this scale — you can't debug a response that changes every time you
ask for it.

This document is the dogfood test for the endpoint: we capture a real response
against seeded data and confirm an LLM can answer concrete questions about the
part from that single response alone.

## The test prompt

```
Here is the current state of part THE-HOMER-001:

[paste /context response]

Questions:
1. How many Homers are currently in assembly?
2. Are there any open purchase orders for this part?
3. What are the components in the Homer's bill of materials?
4. What was the most recent lifecycle event?
```

## The actual `/context` response

Captured via a live HTTP request against the seeded development database. The
API requires a Stytch session since JAS-75/78, so the capture authenticates as
a seeded demo persona first (see the README's auth section):

```bash
bin/dev-op bin/rails db:prepare          # bin/dev-op injects RAILS_MASTER_KEY from 1Password
bin/dev-op bin/rails server -p 3000

JWT=$(curl -s -X POST http://localhost:3000/demo-sessions \
  -H 'Content-Type: application/json' \
  -d '{"email":"dr.quinn@example.com"}' | jq -r .session_jwt)

curl -s http://localhost:3000/parts/THE-HOMER-001/context \
  -H "Authorization: Bearer $JWT" | jq .
```

```json
{
  "partNumber": "THE-HOMER-001",
  "name": "The Homer",
  "revision": "B",
  "status": "RELEASED",
  "summary": "The Homer. Rev B released. 23 instances created, 9 in assembly, 3 certified.",
  "inventory": {
    "total": 23,
    "byStatus": {
      "INSPECTED": 1,
      "VALIDATED": 1,
      "INSTALLED": 2,
      "ORDERED": 2,
      "IN_ASSEMBLY": 9,
      "CERTIFIED": 3,
      "RECEIVED": 5
    }
  },
  "openPurchaseOrders": 2,
  "bom": [
    {
      "partNumber": "ENGINE-V8-001",
      "name": "V8 Engine",
      "quantity": 1,
      "stockAvailable": 49
    },
    {
      "partNumber": "DOME-TRANS-001",
      "name": "Transparent Dome",
      "quantity": 1,
      "stockAvailable": 60
    },
    {
      "partNumber": "HORN-LCC-001",
      "name": "La Cucaracha Horn",
      "quantity": 3,
      "stockAvailable": 111
    },
    {
      "partNumber": "MUZZLE-001",
      "name": "Muzzle",
      "quantity": 1,
      "stockAvailable": 75
    }
  ],
  "recentEvents": [
    {
      "serialNumber": "HMR-0017",
      "eventType": "CERTIFIED",
      "occurredAt": "2026-05-28T10:58:00Z",
      "actor": "jamie.torres@example.com",
      "notes": "HMR-0017 -> CERTIFIED"
    },
    {
      "serialNumber": "HMR-0017",
      "eventType": "VALIDATED",
      "occurredAt": "2026-05-28T10:57:00Z",
      "actor": "jamie.torres@example.com",
      "notes": "HMR-0017 -> VALIDATED"
    },
    {
      "serialNumber": "HMR-0017",
      "eventType": "INSTALLED",
      "occurredAt": "2026-05-28T10:56:00Z",
      "actor": "jamie.torres@example.com",
      "notes": "HMR-0017 -> INSTALLED"
    },
    {
      "serialNumber": "HMR-0017",
      "eventType": "IN_ASSEMBLY",
      "occurredAt": "2026-05-28T10:55:00Z",
      "actor": "jamie.torres@example.com",
      "notes": "HMR-0017 -> IN_ASSEMBLY"
    },
    {
      "serialNumber": "HMR-0017",
      "eventType": "INSPECTED",
      "occurredAt": "2026-05-28T10:54:00Z",
      "actor": "jamie.torres@example.com",
      "notes": "HMR-0017 -> INSPECTED"
    }
  ],
  "generatedAt": "2026-06-04T14:46:43Z"
}
```

## Answers, derived directly from the response

Every answer below comes straight from a field in the single response above — no
external lookup, no follow-up request.

1. **How many Homers are currently in assembly?**
   **9.** From `inventory.byStatus.IN_ASSEMBLY = 9` (and corroborated by the
   `summary`: "…9 in assembly…").

2. **Are there any open purchase orders for this part?**
   **Yes — 2 open purchase orders.** From `openPurchaseOrders = 2`. (This counts
   supplier POs in `OPEN` or `PARTIALLY_RECEIVED` status that have a line for
   this part.)

3. **What are the components in the Homer's bill of materials?**
   Four components, from the `bom` array:
   - `HORN-LCC-001` — La Cucaracha Horn (quantity 3, 111 available)
   - `DOME-TRANS-001` — Transparent Dome (quantity 1, 60 available)
   - `MUZZLE-001` — Muzzle (quantity 1, 75 available)
   - `ENGINE-V8-001` — V8 Engine (quantity 1, 49 available)

   `stockAvailable` is on-hand minus reserved per component.

4. **What was the most recent lifecycle event?**
   **`CERTIFIED` on serial number `HMR-0017`, at `2026-05-28T10:58:00Z`, by
   `jamie.torres@example.com`** ("HMR-0017 -> CERTIFIED"). It is the first
   element of `recentEvents`, which is ordered by `occurredAt` descending, so the
   first entry is the newest event across all instances of this part.

## Validation

Validated by pasting this single `/context` response into Claude alongside the
test prompt above: Claude answered all four questions correctly and completely
from the one response, with no "I don't have enough information" follow-ups —
which is the acceptance bar for this endpoint. Last re-validated 2026-06-04,
against the post-auth API (JAS-75/78) and the full Track 1–9 seed dataset.

## Note on the dataset

This response was captured against the full seed dataset (Tracks 1–9, a fresh
`db:reset`): 23 `THE-HOMER-001` instances across all seven lifecycle statuses
(2 ORDERED, 5 RECEIVED, 1 INSPECTED, 9 IN_ASSEMBLY, 2 INSTALLED, 1 VALIDATED,
3 CERTIFIED), two open supplier POs, a four-component BOM with non-zero
`stockAvailable` on every child, and lifecycle events recorded by the seeded
demo personas (see the README). The answers above are derived from whatever the
current seeds produce — re-running the capture after a reseed should only shift
timestamps, not the shape of the response.
