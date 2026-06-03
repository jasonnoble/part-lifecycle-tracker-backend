# Request specs run against the real Authentication concern, but stub the Stytch
# verification boundary (StytchAuthenticator) so no network/JWKS work happens.
#
# By default every request spec is authenticated as a generic (unseeded) session
# so existing specs keep passing without sending headers. Override per-example
# with `sign_in(user)`, `sign_in_stytch_user(id)`, or `sign_out`.
module AuthenticationHelpers
  DEFAULT_STYTCH_USER_ID = "stub-stytch-session"

  # Authenticate as a specific seeded/created user (resolves current_user).
  def sign_in(user)
    sign_in_stytch_user(user.stytch_user_id)
  end

  # Authenticate as an arbitrary Stytch user_id (use an unseeded id to exercise
  # the authenticated read-only / no-role path).
  def sign_in_stytch_user(stytch_user_id)
    allow(StytchAuthenticator).to receive(:user_id_for).and_return(stytch_user_id)
  end

  # Simulate a missing/invalid/expired session → 401.
  def sign_out
    allow(StytchAuthenticator).to receive(:user_id_for).and_return(nil)
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request

  config.before(:each, type: :request) do
    sign_in_stytch_user(AuthenticationHelpers::DEFAULT_STYTCH_USER_ID)
  end
end
