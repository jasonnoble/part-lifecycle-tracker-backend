# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  # Run the suite with OPENAPI=1 so it also regenerates doc/openapi.yaml, then
  # fail if the committed spec drifted from what the request specs produce.
  step "Tests: RSpec (regenerates OpenAPI doc)", "OPENAPI=1 bundle exec rspec"
  step "Docs: OpenAPI doc is committed and current", "git diff --exit-code doc/openapi.yaml"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"


  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
