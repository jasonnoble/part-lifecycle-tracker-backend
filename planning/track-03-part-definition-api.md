# Track 3 — Part Definition API

**Milestone:** Track 3 — Part Definition API  
**Estimated time:** 4 hours  
**Discussion time:** ~15 minutes

---

## Goal

Full CRUD for Part Definitions plus BOM management. This is the "design artifact" half of the two-entity split. No instance logic here — just defining what a part is and what it's made of.

---

## Key decisions

**Status transitions via dedicated endpoint, not PATCH** — `POST /parts/:id/status` instead of `PATCH /parts/:id` with a `status` field. Reason: state transitions need validation logic (can't go RELEASED → DRAFT, OBSOLETE is terminal). A dedicated endpoint makes the valid transitions explicit and gives a clean place to put the guard logic. `aasm` manages the state machine.

**Revision is writable only in DRAFT** — Once a part is RELEASED, the revision field is locked. If you need to change the revision, you're really making a new version of the part — copy it and get a new UUID. The UI should reflect this by disabling the revision field for non-DRAFT parts.

**Soft-deleted BOM items remain in API responses** — `deleted_at` is set, not a hard delete. Responses include soft-deleted items with `deleted_at` populated so the UI can render them with strikethrough. This preserves the historical record — a work order that referenced a now-deleted BOM item can still show what it was.

**BOM response: Option B (flat list with embedded dependency objects)** — Rather than a normalized response where you'd have to join BOM items with their dependencies separately, each BOM item in the response includes an embedded `dependencies` array listing the `bom_item_id`s that must be completed before it. Simpler for API consumers to reason about.

**Cannot add BOM items to a non-DRAFT part** — Guards in the BOM controller. Once a part is RELEASED, the BOM is locked. This enforces the design artifact lifecycle.

**OpenAPI docs start here and iterate every track** — Rather than generate API docs as a Track 10 polish step, we bootstrap `rspec-openapi` against the *first* endpoints (this track) and regenerate `doc/openapi.yaml` from the request specs as each subsequent API track lands. Generation is a byproduct of `OPENAPI=1 bundle exec rspec` — no DSL, no second copy — so the doc is accurate by construction and the AI-agent contract grows in lockstep with the API. (Supersedes the original `rswag` plan; see `decisions-a-vs-b.md`.) Track 10 keeps only the *finalize & polish* pass.

---

## Stories

### Implement Part Definition CRUD endpoints
**Labels:** backend, api  
**What:** `GET /parts`, `POST /parts`, `GET /parts/:id`, `PATCH /parts/:id`

Endpoints:
- `GET /parts` — list, paginated (Pagy), supports `?status=RELEASED` and `?search=` (name or part_number ILIKE)
- `POST /parts` — create with name, part_number, description, revision (status defaults to DRAFT)
- `GET /parts/:id` — fetch by UUID or part_number (either should work)
- `PATCH /parts/:id` — update name, description; update revision only if DRAFT; status not patchable here

**Acceptance criteria:**
- List endpoint paginated under `meta.pagination`
- Attempting to PATCH revision on a RELEASED part returns 422 with `code: REVISION_LOCKED`
- Attempting to PATCH status directly returns 422 (must use /status endpoint)
- 404 if part not found

### Implement Part status lifecycle endpoint
**Labels:** backend, api  
**What:** `POST /parts/:id/status` — moves through DRAFT → RELEASED → OBSOLETE

Valid transitions:
- DRAFT → RELEASED
- RELEASED → OBSOLETE
- OBSOLETE → (none, terminal)
- DRAFT → OBSOLETE (allowed — abandoning a draft)

Body: `{ "status": "RELEASED" }`

**Acceptance criteria:**
- Invalid transition returns 422 with `code: INVALID_TRANSITION` and message naming both current and target status
- OBSOLETE → anything returns 422 (terminal state)
- RELEASED → DRAFT returns 422 (no going back — copy the part instead)
- Successful transition returns the updated part object

### Implement BOM endpoints
**Labels:** backend, api  
**What:** `GET /parts/:id/bom`, `POST /parts/:id/bom`, `DELETE /parts/:id/bom/:bomItemId`

GET response shape per BOM item:
```json
{
  "id": "uuid",
  "childPartNumber": "HORN-LCC-001",
  "childPartName": "La Cucaracha Horn",
  "quantity": 3,
  "deletedAt": null,
  "dependencies": [
    { "prerequisiteBomItemId": "uuid", "prerequisitePartNumber": "MUZZLE-001" }
  ]
}
```

POST body:
```json
{
  "childPartNumber": "HORN-LCC-001",
  "quantity": 3,
  "prerequisites": ["<bom_item_id>"]
}
```

DELETE: soft delete (sets `deleted_at`)

**Acceptance criteria:**
- GET includes soft-deleted items with `deletedAt` set (not filtered out)
- POST returns 422 if part is not in DRAFT status
- POST returns 422 if `childPartNumber` doesn't exist
- DELETE sets `deleted_at`, returns 200 with updated item
- Dependencies embedded in response (Option B)

### Write RSpec request specs for Part Definition API
**Labels:** test  
**What:** Full request spec coverage for CRUD, status transitions, and BOM management.

Key scenarios:
- Create part, list it, fetch it, update name
- PATCH revision on DRAFT → succeeds
- PATCH revision on RELEASED → 422 REVISION_LOCKED
- POST /status DRAFT → RELEASED → OBSOLETE → attempt any transition → 422
- POST /status RELEASED → DRAFT → 422
- Add BOM item to DRAFT part
- Add BOM item to RELEASED part → 422
- Soft delete BOM item, verify it appears in GET with deletedAt

**Acceptance criteria:**
- All specs use real PostgreSQL
- No mocking of models or DB calls
- Each spec is independent (DatabaseCleaner handles teardown)

### Bootstrap OpenAPI generation with rspec-openapi
**Labels:** api, backend  
**What:** Stand up `rspec-openapi` against the first endpoints so the API doc exists from day one and grows with the API. Generated from the Part Definition request specs (above) — no DSL.

- Add `rspec-openapi` to the Gemfile (test group)
- `OPENAPI=1 bundle exec rspec` generates `doc/openapi.yaml`
- Serve the spec at `/api-docs` in development (Redoc/Scalar/Swagger UI — pick one viewer)
- Commit the generated `doc/openapi.yaml`

**Acceptance criteria:**
- `OPENAPI=1 bundle exec rspec` produces `doc/openapi.yaml` covering the Part Definition + BOM endpoints
- Schemas (params, request bodies, responses, status codes, `{ error, code }`) reflect actual behavior, derived from real request specs
- `/api-docs` renders the spec in development
- `doc/openapi.yaml` committed; regenerating on an unchanged API produces no diff
- **Convention established:** every subsequent API track (4, 5, 7, 8) regenerates and re-commits the spec as part of its work

### Seed Track 3: Released part with full BOM
**Labels:** seed-data  
**What:** Ensure The Homer is in RELEASED status with its full BOM and at least one dependency, ready for Track 4 to create instances against it.

**Acceptance criteria:**
- THE-HOMER-001 status = RELEASED
- BOM includes muzzle-before-dome dependency row in `bom_item_dependencies`
- Seed is idempotent (find_or_create_by on part_number and bom items)

---

## Blog angles

- "Status transitions via dedicated endpoint, not PATCH" — makes valid transitions explicit, gives guards a home. The aasm gem handles the state machine; the endpoint is just the door.
- "A released part can't go back to draft. If you need to change it, you're making a new version." — This is the moment the data model starts encoding real manufacturing practice.
