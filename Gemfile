source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
# gem "rack-cors"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  gem "faker"

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  gem "rspec-rails", "~> 8.0"
  gem "factory_bot_rails", "~> 6.5"

  # Generates doc/openapi.yaml from request specs (run with OPENAPI=1); no-op otherwise.
  gem "rspec-openapi", "~> 0.18"

  # Code coverage measurement (SimpleCov) + per-PR diff coverage gate (undercover).
  # Both require: false — they're CLI-only / loaded explicitly in spec_helper.
  # (undercover pulls in parser via imagen; auto-requiring it made every rails
  # command print parser's "running 4.0.5" warning at boot.)
  gem "simplecov", require: false
  gem "undercover", require: false
end

group :test do
  gem "shoulda-matchers", "~> 7.0"
end

gem "alba", "~> 3.10"

gem "oj", "~> 3.17"

gem "pagy", "~> 43.5"

# State machines for status lifecycles (Part Definition, PO lines, etc.)
gem "aasm", "~> 5.5"


# Stytch authentication (official backend SDK) — session JWT verification
gem "stytch", "~> 7.0"
gem "rack-cors", "~> 3.0"
