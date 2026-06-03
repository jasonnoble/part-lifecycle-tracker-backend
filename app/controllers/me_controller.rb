# Returns the authenticated user's identity and assigned role, so the SPA
# (JAS-76) can show who is signed in and gate UI affordances. An authenticated
# session that isn't linked to a seeded user resolves to a null identity
# (read-only / no-role per JAS-75) rather than a 401.
class MeController < ApplicationController
  def show
    render json: {
      email: current_user&.email,
      name: current_user&.name,
      role: current_user&.role
    }
  end
end
