# Authenticates every request from a Stytch session JWT (Authorization: Bearer).
#
# A valid session is required for all endpoints — no valid session yields 401.
# Identity (the Stytch user_id) is resolved to a `users` record to populate
# `current_user`. An authenticated request whose user_id is not linked to a
# seeded user is still allowed through (read-only / no-role per JAS-75); the
# role-based write gates that consume `current_user` arrive in JAS-79.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_session!
    attr_reader :current_user
  end

  private

  def authenticate_session!
    @stytch_user_id = StytchAuthenticator.user_id_for(bearer_token)
    return render_unauthenticated if @stytch_user_id.blank?

    # May be nil for an authenticated-but-unseeded identity (read-only/no-role).
    @current_user = User.find_by(stytch_user_id: @stytch_user_id)
  end

  def bearer_token
    request.authorization.to_s[/\ABearer (.+)\z/, 1]
  end

  def render_unauthenticated
    render_error("Authentication required", "UNAUTHENTICATED", :unauthorized)
  end
end
