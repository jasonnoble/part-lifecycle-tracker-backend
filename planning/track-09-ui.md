# Track 9 — UI

**Milestone:** Track 9 — UI  
**Estimated time:** 8 hours

---

## Goal

Five screens that make the system usable without explanation. The demo fails if any step requires explaining what the UI is doing. The interface should be self-evident to a first-time user.

---

## Key decisions

**Role selector dropdown, not real auth** — A dropdown in the header persists the current role in the Rails session. Roles: Sarah Chen (Salesperson), Marcus Webb (Floor Manager), Jamie Torres (Tech 1 / Installer), Riley Park (Tech 2 / Validator), Dr. Quinn (QA Engineer), Alex Reyes (Site Manager). No passwords, no login. Auth is v1.

**Role-based action buttons** — The work order screen shows different action buttons based on the current role and step status. Tech 1 and Tech 2 both see an Install button on PENDING steps. Once a step is INSTALLED, the person who installed it sees only the status — the other tech sees a Validate button. QA sees a Certify button on VALIDATED steps. The UI enforces the same 4-eyes logic the API does.

**Tabs for the assembly flow** — The main layout has: Assembly Line tab (Installers, QA, Completed sub-sections), Sales tab (Customer Orders), Parts tab. This mirrors how different roles think about the work.

**Blocked steps show the reason inline** — If a step is blocked (dependency not met or stock unavailable), the reason is visible inline in the step list. Not a tooltip — actual text. The tech should never need to ask "why is this blocked?"

**Read-only Instance Detail** — No editing on this screen. The event log is the source of truth. The only thing you can do here is read.

---

## Stories

### Build Parts List screen
**Labels:** frontend  
**What:** Searchable table of all part definitions with status badges. "New Part" button. Clicking a row navigates to part detail.

Features:
- Search by name or part number (debounced, no page reload)
- Status badges: DRAFT (gray), RELEASED (green), OBSOLETE (red/muted)
- "New Part" opens a create form (modal or slide-over)
- Create form: part number, name, description, revision

**Acceptance criteria:**
- Search filters live without page reload
- Status badges are color-coded
- Create form validates required fields before submit
- New part appears in list after creation

### Build Part Detail screen
**Labels:** frontend  
**What:** Part number, name, revision, status with transition controls. BOM as flat list. Instance count by status. "View /context" button.

Features:
- Status transition button (DRAFT → "Release", RELEASED → "Obsolete")
- BOM list with quantities; soft-deleted items struck through with deleted_at date
- "Add BOM Item" form (only shown for DRAFT parts)
- Instance count by status (read-only summary)
- "View /context Response" button opens raw JSON in a modal

**Acceptance criteria:**
- Status transition button disabled/hidden for invalid transitions
- Soft-deleted BOM items visible with strikethrough, not hidden
- /context raw response visible for debugging
- "Add BOM Item" only available when status = DRAFT

### Build Work Order screen
**Labels:** frontend  
**What:** Step list with role-based action buttons. The assembly floor view.

Layout: Role selector in header. Tabs: Assembly Line / QA / Completed.

Step list columns: Part name, qty, status, action button

Action button logic:
- PENDING: "Install" button (Tech 1 and Tech 2)
- INSTALLED: No action for the installer; "Validate" button for everyone else
- VALIDATED: "Certify" button for QA role only
- CERTIFIED: Status badge only (no action)
- BLOCKED: Status shows blocking reason inline (e.g. "Waiting for Muzzle")

Install form: installed serial number input, submit
Validate form: confirmation only (actor auto-filled from role)
Certify form: confirmation only

Complete Work Order button: disabled until all steps CERTIFIED

**Acceptance criteria:**
- Correct action button based on step status AND current role
- Same-actor validation rejection visible in UI (not just API error)
- Blocked step shows blocking part name inline
- Complete button disabled until all steps CERTIFIED
- Role selector persists across page reloads (session)

### Build Instance Detail screen
**Labels:** frontend  
**What:** Serial number, current status, full lifecycle event log, test records. Read-only.

Layout:
- Header: serial number, part name, current status badge
- Event log: ordered by occurred_at ASC, each row shows: event type badge, actor, occurred_at, recorded_at (small/secondary), notes
- Test records: ordered by occurred_at DESC, each row shows: test type, result badge (PASS=green, FAIL=red, INCONCLUSIVE=yellow), conducted_by, occurred_at, notes

**Acceptance criteria:**
- Events ordered by occurred_at ASC
- Both occurred_at and recorded_at visible (recorded_at secondary)
- Test result badges are color-coded
- No editing anywhere on this screen

### Build Sales / Customer Orders screen
**Labels:** frontend  
**What:** List of customer orders with fulfillment status. "New Customer Order" button.

Visible to: Salesperson, Site Manager roles

Features:
- List of orders with: customer name, line count, status badge, created_at
- "New Customer Order" opens form: customer name + line items (part selector + quantity)
- Order detail (click row): shows lines with fulfillment status (in-stock/reserved vs needs-ordering)

**Acceptance criteria:**
- Only visible to Salesperson and Site Manager roles
- New order form allows adding multiple lines
- Order detail shows whether each line is in-stock or pending supplier PO
- Status badge: OPEN / IN_FULFILLMENT / COMPLETE

### Seed Track 9: UI-ready seed data
**Labels:** seed-data  
**What:** Final comprehensive seed ensuring all 5 screens have meaningful data.

Required state:
- Parts list: 3 parts (THE-HOMER-001 RELEASED, MARGE-FAM-001 DRAFT, BART-HOT-001 DRAFT)
- Work orders: one OPEN with mixed step statuses, one COMPLETE, one BLOCKED
- Customer orders: one OPEN, one IN_FULFILLMENT, one COMPLETE
- Instance detail: HMR-0047 has full event history through CERTIFIED

**Acceptance criteria:**
- No empty states on any screen with seed data loaded
- Work order screen shows at least one blocked step with reason
- Parts list search returns results for "homer" and "marge"
- Seed is idempotent

---

## Blog angles

- "The demo fails if any step requires explaining what the UI is doing." This was the acceptance criterion for the entire UI track. It forced every ambiguous state to have visible explanation.
- Role-based action buttons without auth: "v0 is one dropdown and a session cookie. That's enough to demo the 4-eyes workflow without building an auth system."
- The blocked step showing its reason inline: "If you have to hover to find out why something is blocked, the UI is already broken."
