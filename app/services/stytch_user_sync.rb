# Links a User to its Stytch identity: finds the Stytch user by email (reusing
# it) or creates one, then persists the opaque user_id onto user.stytch_user_id
# (the JWT `sub` that session verification resolves against — see JAS-78).
#
# Idempotent and safe to re-run: a User that's already linked is left untouched,
# and an unlinked one is matched to any existing Stytch user before creating a
# new one. This is the provisioning counterpart to StytchAuthenticator; run it
# (e.g. via `rails stytch:sync_users`) once per environment / Stytch project.
class StytchUserSync
  def self.call(user) = new.call(user)

  def initialize(client: StytchClient.build)
    @client = client
  end

  def call(user)
    return user if user.stytch_user_id.present?

    stytch_user_id = find_by_email(user.email) || create(user)
    user.update!(stytch_user_id: stytch_user_id) if stytch_user_id.present?
    user
  end

  private

  def find_by_email(email)
    @client.users.search(
      query: { operator: "OR", operands: [ { filter_name: "email_address", filter_value: [ email ] } ] }
    ).dig("results", 0, "user_id")
  end

  def create(user)
    @client.users.create(email: user.email)["user_id"]
  end
end
