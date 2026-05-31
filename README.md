# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## Code coverage

Test coverage is measured by [SimpleCov](https://github.com/simplecov-ruby/simplecov)
and gated per-PR by [undercover](https://github.com/grodowski/undercover).

* Running `bundle exec rspec` writes a browsable HTML report to `coverage/index.html`
  and `coverage/coverage.json` (consumed by undercover). Branch coverage is enabled.
  `coverage/` is gitignored — no baseline file is committed.
* **Diff gate:** every PR must keep new or changed Ruby code covered. The undercover
  step (`bundle exec undercover --compare <base>`) fails the build when changed
  blocks lack a test. This enforces "a merge can only keep coverage the same or
  raise it" by construction, without persisting a baseline percentage.
* **Floor:** `SimpleCov.minimum_coverage` in `spec/spec_helper.rb` is a coarse
  safety floor set to the measured baseline (line 79% / branch 95%). It is
  **ratchet-up only** — raise it as coverage improves; never lower it.

Native build note: undercover depends on `rugged`, whose native extension needs
`cmake` and `pkg-config` (`brew install cmake pkg-config` on macOS).
