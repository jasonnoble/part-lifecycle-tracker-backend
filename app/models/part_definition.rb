class PartDefinition < ApplicationRecord
  include AASM

  STATUSES = %w[DRAFT RELEASED OBSOLETE].freeze

  has_many :bom_items, foreign_key: :parent_part_definition_id, dependent: :destroy
  has_one :stock, dependent: :destroy

  validates :part_number, presence: true, uniqueness: true
  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :by_status, ->(status) { where(status: status) }
  scope :search, ->(query) {
    term = "%#{sanitize_sql_like(query.to_s)}%"
    where("name ILIKE :term OR part_number ILIKE :term", term: term)
  }

  # State names are intentionally UPPERCASE so they match the values persisted in
  # the `status` column (enforced by the part_definitions_status_check constraint
  # and written by the seeds). AASM persists the state *name* verbatim and reads it
  # back with `to_sym`, so the name must equal the stored string — it has no
  # separate value-mapping in this version. The transition *endpoint* lands in
  # JAS-21; the state machine lives here so transitions have one source of truth.
  aasm column: :status, whiny_transitions: false do
    state :DRAFT, initial: true
    state :RELEASED
    state :OBSOLETE

    event :release do
      transitions from: :DRAFT, to: :RELEASED
    end

    event :obsolete do
      transitions from: %i[DRAFT RELEASED], to: :OBSOLETE
    end
  end
end
