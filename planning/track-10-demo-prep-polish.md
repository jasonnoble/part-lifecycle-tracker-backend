# Track 10 — Demo Prep & Polish

**Milestone:** Track 10 — Demo Prep & Polish  
**Estimated time:** 4 hours

---

## Goal

The system works. Now make it shippable. This track is about running the demo end-to-end, fixing anything that requires explanation, writing the ADRs that become the blog post material, and making sure someone else can clone the repo and run the demo in under 10 minutes.

---

## Key decisions

**ADRs are first-class artifacts** — Five Architecture Decision Records, one per major design decision. Written in `docs/adr/`. Each one is a blog post section waiting to be expanded. Format: Context / Decision / Consequences + the blog story angle.

**OpenAPI: finalize, don't build** — Generation was bootstrapped in Track 3 with `rspec-openapi` and regenerated each API track, so by now the spec already covers every endpoint. This track is the *polish* pass only: hand-author descriptions/examples, confirm the `/api-docs` viewer, and commit the final `doc/openapi.yaml`. AI agents are a first-class consumer; they need a machine-readable spec, and code-first generation keeps it accurate by construction. (We chose `rspec-openapi` over the originally-planned `rswag` — see `decisions-a-vs-b.md`.)

**The 7-step demo is the integration test** — Before marking this track done, run every step in the success criteria from the PRD. Fix anything that requires explaining. This is the real acceptance test.

---

## Stories

### Write ADRs for 5 key design decisions
**Labels:** backend  
**What:** Five Architecture Decision Records in `docs/adr/`.

ADRs to write:
1. `adr-001-definition-vs-instance.md` — Why Part Definition and Part Instance are separate entities
2. `adr-002-append-only-events.md` — Why lifecycle events are append-only and never updated
3. `adr-003-atomic-po-receive.md` — Why PO receive is one atomic endpoint instead of three separate operations
4. `adr-004-templated-context-summary.md` — Why /context returns a templated summary string instead of calling an LLM
5. `adr-005-409-dependency-enforcement.md` — Why dependency enforcement returns a 409 instead of a warning

Each ADR format:
```
# ADR-NNN: Title

## Status
Accepted

## Context
[Why this decision was needed]

## Decision
[What was decided]

## Consequences
[What this means going forward]

## Blog angle
[One sentence on why this is interesting for the "How I Built This" post]
```

**Acceptance criteria:**
- All 5 ADRs written and committed to `docs/adr/`
- Each ADR references the alternative that was rejected
- Blog angle section filled in for each

### End-to-end demo run and fix
**Labels:** test  
**What:** Run the full 7-step success criteria scenario from the PRD. Document friction. Fix anything that requires explanation.

The 7 steps:
1. Create a part definition with a BOM that has one dependency
2. Create a purchase order, receive it, see instances appear
3. Open a work order, attempt to complete the dependent step first, see it blocked
4. Complete the prerequisite step, then complete the dependent step
5. Record a test result against the finished instance
6. Complete the work order
7. Call /context and verify the response reflects current state

**Acceptance criteria:**
- All 7 steps complete without explanation
- No UI states that leave a user unsure of the next action
- Any friction found is fixed before marking this story done
- Demo run documented in a 2-3 sentence note in the README

### Write README with setup and demo instructions
**Labels:** infra  
**What:** `README.md` covering local setup, seed data, and the 7-step demo.

Sections:
- What this is (2 sentences)
- Local setup: clone, bundle, db:create, db:migrate, db:seed, rails s
- Running tests: bin/rspec
- The demo: numbered 7-step walkthrough
- Key API calls: curl examples for /context, PO receive, work order step completion
- Architecture: link to docs/adr/ for design decisions
- Deployment: Kamal 2 to Hetzner

**Acceptance criteria:**
- Developer can clone repo and run demo in under 10 minutes
- All curl examples tested and working
- Link to /context dogfood test document

### Finalize & polish the OpenAPI spec
**Labels:** api, backend  
**What:** Final pass on the `rspec-openapi`-generated `doc/openapi.yaml` (bootstrapped in Track 3, regenerated each API track). Not a from-scratch build — coverage already exists; this is polish.

- Regenerate from the full suite (`OPENAPI=1 bundle exec rspec`) and confirm every endpoint is present
- Hand-author descriptions, summaries, and a couple of representative examples (these survive regeneration)
- Confirm the `/api-docs` viewer renders cleanly
- Commit the final `doc/openapi.yaml`

**Acceptance criteria:**
- Every endpoint documented with request/response schemas, derived from real specs (no hand-written schema drift)
- `/api-docs` accessible in development
- Final `doc/openapi.yaml` committed; a clean regenerate produces no unexpected diff
- Hand-authored descriptions/examples present on the key endpoints (`/context`, PO receive, work-order step actions)

### Seed Track 10: Final demo dataset
**Labels:** seed-data  
**What:** Ensure `rails db:seed` on a fresh database produces a state where all 7 demo steps can be executed end-to-end.

The seed should produce:
- The Homer (THE-HOMER-001) RELEASED with full BOM and muzzle-before-dome dependency
- Stock: enough horn units and other parts to receive a PO
- An open Supplier PO ready to be received (so step 2 can be demonstrated)
- A work order in progress (for step 3-6 demonstration)
- HMR-0047 with complete lifecycle history (for reference)

**Acceptance criteria:**
- All 7 demo steps can be completed immediately after `rails db:seed`
- Demo dataset documented in README
- Seed is idempotent

---

## Blog angles

- "The demo is the acceptance test. If it requires explanation, it's not done." This is the headline for Track 10.
- ADRs as blog material: "I wrote the ADRs last but they document decisions made first. The interesting part isn't the conclusion — it's everything we ruled out and why."
- The dogfood test in Track 8 and the demo run in Track 10 are the two moments where you know the system actually works. Everything else is building toward them.
