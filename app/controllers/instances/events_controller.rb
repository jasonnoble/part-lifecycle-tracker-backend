module Instances
  # Append-only lifecycle event log for a part instance, nested under
  # /instances/:instance_serial/events. Standard RESTful index/create actions.
  class EventsController < ApplicationController
    before_action :set_instance

    def index
      @pagy, events = pagy(:offset, @instance.lifecycle_events.chronological)

      render json: {
        data: LifecycleEventSerializer.new(events).serializable_hash,
        meta: pagination_meta(@pagy)
      }
    end

    def create
      event = @instance.lifecycle_events.new(event_params)

      # recorded_at is ALWAYS server-set and never accepted from the client.
      event.recorded_at = Time.current

      PartInstance.transaction do
        event.save!
        @instance.update!(current_status: event.event_type)
      end

      render json: LifecycleEventSerializer.new(event).serializable_hash, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render_validation_errors(e.record)
    end

    private

    def set_instance
      @instance = PartInstance.includes(:part_definition).find_by!(serial_number: params[:instance_serial])
    end

    def event_params
      {
        event_type: params[:eventType],
        actor: params[:actor],
        notes: params[:notes],
        metadata: params[:metadata],
        occurred_at: params[:occurredAt]
      }
    end
  end
end
