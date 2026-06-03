# Verifies a Stytch session JWT and returns the authenticated Stytch user_id
# (the JWT `sub`), or nil when the token is missing/invalid/expired.
#
# Verification is local (JWKS signature check, no network round-trip) for tokens
# within MAX_TOKEN_AGE_SECONDS; the SDK transparently falls back to the Stytch
# API for older tokens. We deliberately resolve only the opaque user_id here —
# the acting role is derived from the `users` record downstream, never trusted
# from the token (see JAS-75).
class StytchAuthenticator
  # Stytch session JWTs are short-lived; 300s is the SDK default before it
  # re-checks against the API.
  MAX_TOKEN_AGE_SECONDS = 300

  # Errors that mean "this token is not valid" — swallowed into a nil result so
  # the caller renders 401. Configuration errors (missing credentials) are NOT
  # listed, so a misconfigured deploy fails loudly instead of 401-ing everyone.
  VERIFICATION_ERRORS = [
    Stytch::JWTExpiredSignatureError,
    Stytch::JWTExpiredError,
    Stytch::JWTInvalidIssuerError,
    Stytch::JWTInvalidAudienceError,
    Stytch::JWTIncorrectAlgorithmError,
    JWT::DecodeError,
    Faraday::Error
  ].freeze

  def self.user_id_for(session_jwt)
    new.user_id_for(session_jwt)
  end

  def user_id_for(session_jwt)
    return if session_jwt.blank?

    response = client.sessions.authenticate_jwt(session_jwt, max_token_age_seconds: MAX_TOKEN_AGE_SECONDS)
    response.dig("session", "user_id").presence
  rescue *VERIFICATION_ERRORS => e
    Rails.logger.info("[Stytch] session verification failed: #{e.class}")
    nil
  end

  private

  def client
    @client ||= Stytch::Client.new(
      project_id: config.fetch(:project_id),
      secret: config.fetch(:secret),
      env: config[:env]
    )
  end

  # `env` is optional — the SDK infers live vs. test from the project_id prefix.
  def config
    Rails.application.credentials.stytch || {}
  end
end
