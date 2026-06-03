# Single source of truth for the role -> action authorization matrix (JAS-79).
# Controllers ask `Permissions.can?(current_user, "step.certify")`; /me exposes
# `Permissions.for(current_user)` so the SPA gates its UI from the same policy
# instead of re-implementing it client-side.
#
# Deliberately NOT here: the four-eyes rule (validator != installer) — that's a
# domain invariant about identity, enforced in the controller with the
# work_order_steps_four_eyes DB CHECK as backstop — and the blanket
# "writes require a seeded identity" gate, which lives in the Authentication
# concern (no identity => read-only, regardless of action).
class Permissions
  ALL_ROLES = User.roles.keys.freeze

  # Ability => roles allowed. Unknown abilities raise (fail loud on typos).
  ABILITIES = {
    "step.install" => ALL_ROLES,
    "step.validate" => ALL_ROLES,
    "step.certify" => %w[qa_engineer].freeze,
    "instance.record_event" => ALL_ROLES,
    "instance.record_test" => ALL_ROLES
  }.freeze

  def self.can?(user, ability)
    user.present? && ABILITIES.fetch(ability).include?(user.role)
  end

  # The abilities granted to this user (empty for read-only/no-role sessions).
  def self.for(user)
    ABILITIES.keys.select { |ability| can?(user, ability) }
  end
end
