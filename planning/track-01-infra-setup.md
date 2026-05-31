# Track 1 — Infra & Setup

**Milestone:** Track 1 — Infra & Setup  
**Estimated time:** 4 hours  
**Linear issues:** JAS-5 through JAS-10

---

## Goal

Get a deployable Rails 8 API app running at `partledger.jasonnoble.dev` with the test harness and foundational gems in place. Nothing domain-specific ships in this track — just the skeleton that every other track builds on.

---

## Key decisions

**Same Hetzner box** — Already running jasonnoble.dev on a CPX21. Adding a second Kamal service costs nothing and avoids cold starts on demos. Railway's free tier has cold starts; this doesn't.

**Subdomain over new domain** — `partledger.jasonnoble.dev` via Cloudflare. No registration cost, DNS is already managed there, TLS via Let's Encrypt through Kamal.

**Kamal 2** — Matches the existing jasonnoble.dev deployment. Zero-downtime deploys from git push.

**Individual migrations** — Small, focused, reversible. One table per migration. No monster "initial schema" migration.

**Real PostgreSQL in tests** — No mocking the DB layer. This is called out in the instructions explicitly: RSpec specs use a real Postgres test database. Pagy from the start on all list endpoints.

---

## Stories

### JAS-5 — Create GitHub repo and scaffold Rails 8 API app
**Labels:** infra  
**What:** New public GitHub repo `jasonnoble/part-lifecycle-tracker`. Rails 8 in API mode, PostgreSQL adapter, no Action Cable, no Active Storage.  
**Acceptance criteria:**
- `rails new` in API mode with PostgreSQL
- `.ruby-version` set
- `Gemfile` includes: rspec-rails, factory_bot_rails, shoulda-matchers, database_cleaner-active_record, pagy, aasm, rswag
- `rails db:create` succeeds locally
- README placeholder committed

### JAS-6 — Configure RSpec with real PostgreSQL test database
**Labels:** infra, test  
**What:** RSpec configured with real Postgres test DB, DatabaseCleaner using transaction strategy, FactoryBot helpers.  
**Acceptance criteria:**
- `spec/rails_helper.rb` configures DatabaseCleaner with `:transaction` strategy
- `spec/spec_helper.rb` clean
- `bin/rspec` runs green on empty suite
- No DB mocking anywhere in the setup

### JAS-7 — Install and configure Pagy for pagination
**Labels:** infra, backend  
**What:** Pagy gem installed, backend helper included in ApplicationController, consistent pagination metadata in all list responses.  
**Acceptance criteria:**
- `include Pagy::Backend` in ApplicationController
- Pagy metadata included in list responses under `meta.pagination`
- Default page size: 25
- `?page=` and `?per_page=` params honored

### JAS-8 — Configure Kamal 2 for partledger.jasonnoble.dev on Hetzner
**Labels:** infra  
**What:** `config/deploy.yml` configured for the existing Hetzner CPX21 box. Second service alongside jasonnoble.dev.  
**Acceptance criteria:**
- `kamal setup` succeeds
- Service name: `part-lifecycle-tracker`
- PostgreSQL as a Kamal accessory
- Env vars managed via Kamal secrets

### JAS-9 — Add partledger.jasonnoble.dev subdomain in Cloudflare and verify first deploy
**Labels:** infra  
**What:** DNS A record in Cloudflare pointing to Hetzner box IP. TLS via Kamal + Let's Encrypt. First deploy confirms the app is live.  
**Acceptance criteria:**
- `https://partledger.jasonnoble.dev` returns 200
- TLS cert valid
- `GET /` returns `{ status: "ok" }` or similar health check response

### JAS-10 — Set up idempotent seed file foundation
**Labels:** infra, seed-data  
**What:** `db/seeds.rb` calls per-track seed files. Each track will add its own seed file. Running `rails db:seed` multiple times is safe.  
**Acceptance criteria:**
- `db/seeds/` directory with `track_01.rb` as the first file
- `db/seeds.rb` requires all files in `db/seeds/` in order
- Each seed uses `find_or_create_by` (or equivalent) — no duplicates on re-run
- `rails db:seed` produces no errors on a fresh database

---

## Blog angles

- The 72-hour sprint only works because the infra is already there. No provisioning time, no credit card for Railway. The discipline of owning your own server pays off.
- Pagy from day one: pagination as an afterthought is a production incident waiting to happen. Adding it costs 10 minutes and saves an afternoon.
