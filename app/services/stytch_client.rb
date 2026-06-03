# Builds a Stytch SDK client — the single place that reads the Stytch
# project_id/secret. Shared by StytchAuthenticator (session verification)
# and StytchUserSync (user provisioning).
#
# Config is ENV-first (STYTCH_PROJECT_ID/STYTCH_SECRET, injected in production
# via .kamal/secrets → deploy.yml env.secret), falling back to Rails
# credentials for dev/test.
#
# `env` is optional: the SDK infers live vs. test from the project_id prefix.
# Missing credentials raise KeyError (fail loud), rather than silently building
# a broken client.
module StytchClient
  module_function

  def build
    config = env_config || credentials_config
    Stytch::Client.new(
      project_id: config.fetch(:project_id),
      secret: config.fetch(:secret),
      env: config[:env]
    )
  end

  # Only used when both vars are present — a half-set pair falls through to
  # credentials rather than building a client that fails on every request.
  def env_config
    return nil unless ENV["STYTCH_PROJECT_ID"].present? && ENV["STYTCH_SECRET"].present?

    { project_id: ENV["STYTCH_PROJECT_ID"], secret: ENV["STYTCH_SECRET"], env: ENV["STYTCH_ENV"].presence }
  end

  def credentials_config
    Rails.application.credentials.stytch || {}
  end
end
