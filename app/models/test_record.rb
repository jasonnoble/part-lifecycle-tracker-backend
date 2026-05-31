class TestRecord < ApplicationRecord
  # Append-only test result log. Rows are never updated or deleted; there is no
  # updated_at column. result is constrained to RESULTS both here and by the
  # test_records_result_check DB constraint.
  RESULTS = %w[PASS FAIL INCONCLUSIVE].freeze

  belongs_to :part_instance

  validates :test_type, presence: true
  validates :result, inclusion: { in: RESULTS }
  validates :conducted_by, presence: true
  validates :occurred_at, presence: true

  # Most-recent-first ordering; id breaks ties since occurred_at is neither
  # unique nor monotonic (backdated tests, ties).
  scope :recent_first, -> { order(occurred_at: :desc, id: :desc) }
end
