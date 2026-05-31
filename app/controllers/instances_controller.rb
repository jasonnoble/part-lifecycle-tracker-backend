class InstancesController < ApplicationController
  before_action :set_instance, only: :show

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
    render json: PartInstanceSerializer.new(@instance).serializable_hash
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

  private

  def set_instance
    @instance = PartInstance.includes(:part_definition).find_by!(serial_number: params[:serial])
  end
end
