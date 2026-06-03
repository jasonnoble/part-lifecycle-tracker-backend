# Bootstrap for the SPA's one-click "Explore as…" demo logins (JAS-80/JAS-76):
# mints a real Stytch session for one of the six seeded demo personas, so demo
# sessions pass the same Bearer-JWT verification as any other login (JAS-78).
#
# Strictly scoped to the seeded demo emails — anything else 404s without
# touching Stytch, so this can't become a general auth bypass and doesn't leak
# which emails exist.
class DemoSessionsController < ApplicationController
  # This endpoint IS the way to get a session, so it can't require one.
  skip_before_action :authenticate_session!
  skip_before_action :forbid_read_only_writes!

  # The six seeded personas from db/seeds/track_06.rb — keep in lockstep.
  DEMO_EMAILS = %w[
    sarah.chen@example.com
    marcus.webb@example.com
    jamie.torres@example.com
    riley.park@example.com
    dr.quinn@example.com
    alex.reyes@example.com
  ].freeze

  def create
    email = params[:email].to_s.downcase
    user = User.find_by(email: email) if DEMO_EMAILS.include?(email)
    return render_error("Not found", "NOT_FOUND", :not_found) if user.nil?

    render json: StytchDemoSession.mint(user), status: :created
  rescue StytchDemoSession::NotLinkedError => e
    # Config-style failure (seeded user not linked to Stytch) — loud, not a 401.
    render_error(e.message, "DEMO_USER_NOT_LINKED", :internal_server_error)
  end
end
