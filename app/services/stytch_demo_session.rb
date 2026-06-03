# Mints a real Stytch session for a seeded demo persona (JAS-80) via the
# documented server-side embedded magic-link pattern: create a magic-link token
# for the user, then immediately authenticate it — no inbox involved. Returns
# { session_jwt:, session_token: } for the SPA's one-click demo logins.
#
# The user must already be linked to Stytch (stytch_user_id, populated by
# `rails stytch:sync_users`); an unlinked user is a deployment/config problem,
# surfaced loudly as NotLinkedError rather than masquerading as a 401/404.
class StytchDemoSession
  # Matches the SPA's sessionOptions.sessionDurationMinutes (JAS-76).
  SESSION_DURATION_MINUTES = 60

  class NotLinkedError < StandardError; end

  def self.mint(user) = new.mint(user)

  def initialize(client: nil)
    @client = client
  end

  def mint(user)
    if user.stytch_user_id.blank?
      raise NotLinkedError,
            "#{user.email} has no stytch_user_id — run `bin/rails stytch:sync_users` to link seeded users"
    end

    token = client.magic_links.create(user_id: user.stytch_user_id).fetch("token")
    session = client.magic_links.authenticate(token: token, session_duration_minutes: SESSION_DURATION_MINUTES)

    { session_jwt: session.fetch("session_jwt"), session_token: session.fetch("session_token") }
  end

  private

  # Lazy so the NotLinkedError path needs no Stytch credentials (keyless CI).
  def client
    @client ||= StytchClient.build
  end
end
