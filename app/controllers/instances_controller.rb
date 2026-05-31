class InstancesController < ApplicationController
  def index
    scope = PartInstance.includes(:part_definition)
    scope = scope.for_part_number(params[:part_number]) if params[:part_number].present?
    scope = scope.with_status(params[:status]) if params[:status].present?
    scope = scope.order(:serial_number)

    @pagy, instances = pagy(:offset, scope)

    render json: {
      data: PartInstanceSerializer.new(instances).serializable_hash,
      meta: pagination_meta(@pagy)
    }
  end

  def show
    instance = find_instance!
    render json: PartInstanceSerializer.new(instance).serializable_hash
  end

  def create
    part = PartDefinition.find_by(part_number: params[:partNumber])
    unless part
      return render_error("Part definition not found", "VALIDATION_FAILED", :unprocessable_content)
    end

    instance = part.part_instances.new(serial_number: params[:serialNumber], current_status: "RECEIVED")

    # current_status is derived from events, never set directly as the source of
    # truth: create the instance AND its initial RECEIVED event in one transaction.
    PartInstance.transaction do
      instance.save!
      instance.lifecycle_events.create!(
        event_type: "RECEIVED",
        actor: "system",
        occurred_at: Time.current
      )
    end

    render json: PartInstanceSerializer.new(instance).serializable_hash, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors(e.record)
  end

  def events_index
    instance = find_instance!
    @pagy, events = pagy(:offset, instance.lifecycle_events.chronological)

    render json: {
      data: LifecycleEventSerializer.new(events).serializable_hash,
      meta: pagination_meta(@pagy)
    }
  end

  def events_create
    instance = find_instance!
    event = instance.lifecycle_events.new(event_params)

    # recorded_at is ALWAYS server-set and never accepted from the client.
    event.recorded_at = Time.current

    PartInstance.transaction do
      event.save!
      instance.update!(current_status: event.event_type)
    end

    render json: LifecycleEventSerializer.new(event).serializable_hash, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors(e.record)
  end

  private

  def find_instance!
    PartInstance.includes(:part_definition).find_by!(serial_number: params[:serial])
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
