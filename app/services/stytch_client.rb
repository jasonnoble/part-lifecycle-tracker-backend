# Builds a Stytch SDK client from Rails credentials — the single place that
# reads `stytch.project_id` / `stytch.secret`. Shared by StytchAuthenticator
# (session verification) and StytchUserSync (user provisioning).
#
# `env` is optional: the SDK infers live vs. test from the project_id prefix.
# Missing credentials raise KeyError (fail loud), rather than silently building
# a broken client.
module StytchClient
  module_function

  def build
    config = Rails.application.credentials.stytch || {}
    Stytch::Client.new(
      project_id: config.fetch(:project_id),
      secret: config.fetch(:secret),
      env: config[:env]
    )
  end
end
