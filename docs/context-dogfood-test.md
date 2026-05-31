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

Captured via a live HTTP request against the seeded development database:

```bash
bin/rails db:prepare
bin/rails server -p 3010
curl -s http://localhost:3010/parts/THE-HOMER-001/context | python3 -m json.tool
```

```json
{
    "partNumber": "THE-HOMER-001",
    "name": "The Homer",
    "revision": "B",
    "status": "RELEASED",
    "summary": "The Homer. Rev B released. 15 instances created, 7 in assembly, 1 certified.",
    "inventory": {
        "total": 15,
        "byStatus": {
            "CERTIFIED": 1,
            "VALIDATED": 1,
            "INSTALLED": 1,
            "RECEIVED": 5,
            "IN_ASSEMBLY": 7
        }
    },
    "openPurchaseOrders": 1,
    "bom": [
        {
            "partNumber": "HORN-LCC-001",
            "name": "La Cucaracha Horn",
            "quantity": 3,
            "stockAvailable": 0
        },
        {
            "partNumber": "DOME-TRANS-001",
            "name": "Transparent Dome",
            "quantity": 1,
            "stockAvailable": 0
        },
        {
            "partNumber": "MUZZLE-001",
            "name": "Muzzle",
            "quantity": 1,
            "stockAvailable": 0
        },
        {
            "partNumber": "ENGINE-V8-001",
            "name": "V8 Engine",
            "quantity": 1,
            "stockAvailable": 0
        }
    ],
    "recentEvents": [
        {
            "serialNumber": "HMR-0047",
            "eventType": "CERTIFIED",
            "occurredAt": "2026-01-14T14:00:00Z",
            "actor": "qa@factory.example",
            "notes": "Seed: HMR-0047 reached CERTIFIED."
        },
        {
            "serialNumber": "HMR-0047",
            "eventType": "VALIDATED",
            "occurredAt": "2026-01-14T13:00:00Z",
            "actor": "validator@factory.example",
            "notes": "Seed: HMR-0047 reached VALIDATED."
        },
        {
            "serialNumber": "HMR-0047",
            "eventType": "INSTALLED",
            "occurredAt": "2026-01-14T12:00:00Z",
            "actor": "installer@factory.example",
            "notes": "Seed: HMR-0047 reached INSTALLED."
        },
        {
            "serialNumber": "HMR-0047",
            "eventType": "IN_ASSEMBLY",
            "occurredAt": "2026-01-14T11:00:00Z",
            "actor": "assembly@factory.example",
            "notes": "Seed: HMR-0047 reached IN_ASSEMBLY."
        },
        {
            "serialNumber": "HMR-0047",
            "eventType": "INSPECTED",
            "occurredAt": "2026-01-14T10:00:00Z",
            "actor": "inspector@factory.example",
            "notes": "Seed: HMR-0047 reached INSPECTED."
        }
    ],
    "generatedAt": "2026-05-31T13:07:00Z"
}
```

## Answers, derived directly from the response

Every answer below comes straight from a field in the single response above — no
external lookup, no follow-up request.

1. **How many Homers are currently in assembly?**
   **7.** From `inventory.byStatus.IN_ASSEMBLY = 7` (and corroborated by the
   `summary`: "…7 in assembly…").

2. **Are there any open purchase orders for this part?**
   **Yes — 1 open purchase order.** From `openPurchaseOrders = 1`. (This counts
   supplier POs in `OPEN` or `PARTIALLY_RECEIVED` status that have a line for
   this part.)

3. **What are the components in the Homer's bill of materials?**
   Four components, from the `bom` array:
   - `HORN-LCC-001` — La Cucaracha Horn (quantity 3)
   - `DOME-TRANS-001` — Transparent Dome (quantity 1)
   - `MUZZLE-001` — Muzzle (quantity 1)
   - `ENGINE-V8-001` — V8 Engine (quantity 1)

   Each carries a `stockAvailable` value as well (all `0` in this dataset).

4. **What was the most recent lifecycle event?**
   **`CERTIFIED` on serial number `HMR-0047`, at `2026-01-14T14:00:00Z`, by
   `qa@factory.example`** ("Seed: HMR-0047 reached CERTIFIED."). It is the first
   element of `recentEvents`, which is ordered by `occurredAt` descending, so the
   first entry is the newest event across all instances of this part.

## Validation

Validated by pasting this single `/context` response into Claude alongside the
test prompt above: Claude answered all four questions correctly and completely
from the one response, with no "I don't have enough information" follow-ups —
which is the acceptance bar for this endpoint.

## Note on the dataset

This response was generated against the current seed dataset on this branch
(Tracks 1–3): 15 `THE-HOMER-001` instances across five statuses (5 RECEIVED,
7 IN_ASSEMBLY, 1 INSTALLED, 1 VALIDATED, 1 CERTIFIED), one open supplier PO, and
a four-component BOM. It is already non-trivial and demo-worthy. The richer demo
seed (more instances, populated stock so `stockAvailable` is non-zero) lands in a
separate Track 8 seed story (JAS-48); the answers above are derived from whatever
the current seeds produce.
