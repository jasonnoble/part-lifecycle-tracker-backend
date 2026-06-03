module Instances
  # Test records for a part instance, nested under
  # /instances/:instance_serial/tests. Standard RESTful index/create actions.
  class TestsController < ApplicationController
    before_action :set_instance

    def index
      @pagy, records = pagy(:offset, @instance.test_records.recent_first)

      render json: {
        data: TestRecordSerializer.new(records).serializable_hash,
        meta: pagination_meta(@pagy)
      }
    end

    def create
      unless Permissions.can?(current_user, "instance.record_test")
        return render_error(
          "#{current_user.email} is not authorized to record tests (qa_engineer role required)",
          "FORBIDDEN",
          :forbidden
        )
      end

      record = @instance.test_records.new(test_record_params)

      # recorded_at is ALWAYS server-set and never accepted from the client.
      record.recorded_at = Time.current
      record.save!

      render json: TestRecordSerializer.new(record).serializable_hash, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render_validation_errors(e.record)
    end

    private

    def set_instance
      @instance = PartInstance.includes(:part_definition).find_by!(serial_number: params[:instance_serial])
    end

    def test_record_params
      {
        test_type: params[:testType],
        result: params[:result],
        notes: params[:notes],
        # Recorded from the authenticated identity, never client-supplied (JAS-79).
        conducted_by: current_user.email,
        occurred_at: params[:occurredAt]
      }
    end
  end
end
