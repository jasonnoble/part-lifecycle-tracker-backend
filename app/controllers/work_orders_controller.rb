class WorkOrdersController < ApplicationController
  STEP_INCLUDES = { work_order_steps: { bom_item: :child } }.freeze
  ORDER_INCLUDES = [ :part_definition, :part_instance, STEP_INCLUDES ].freeze

  def index
    scope = WorkOrder.includes(*ORDER_INCLUDES).order(created_at: :desc)
    scope = scope.by_status(params[:status]) if params[:status].present?

    @pagy, orders = pagy(:offset, scope)

    render json: {
      data: WorkOrderSerializer.new(orders).serializable_hash,
      meta: pagination_meta(@pagy)
    }
  end

  def show
    order = WorkOrder.includes(*ORDER_INCLUDES).find(params[:id])
    render json: WorkOrderSerializer.new(order).serializable_hash
  end

  def create
    part_number = params[:partNumber]
    serial_number = params[:serialNumber]

    if part_number.blank?
      return render_error("partNumber can't be blank", "VALIDATION_FAILED", :unprocessable_content)
    end

    if serial_number.blank?
      return render_error("serialNumber can't be blank", "VALIDATION_FAILED", :unprocessable_content)
    end

    part_definition = PartDefinition.find_by(part_number: part_number)
    if part_definition.nil?
      return render_error("Unknown partNumber: #{part_number}", "NOT_FOUND", :not_found)
    end

    part_instance = PartInstance.find_by(serial_number: serial_number)
    if part_instance.nil?
      return render_error("Unknown serialNumber: #{serial_number}", "NOT_FOUND", :not_found)
    end

    if WorkOrder.where(part_instance_id: part_instance.id).where.not(status: "COMPLETE").exists?
      return render_error(
        "serialNumber #{serial_number} already has an open work order",
        "OPEN_WORK_ORDER_EXISTS",
        :unprocessable_content
      )
    end

    active_bom_items = part_definition.bom_items.where(deleted_at: nil).order(:created_at, :id)

    order = WorkOrder.new(
      part_definition: part_definition,
      part_instance: part_instance,
      customer_order_line_id: params[:customerOrderLineId],
      status: "OPEN"
    )

    WorkOrder.transaction do
      order.save!
      active_bom_items.each do |bom_item|
        order.work_order_steps.create!(bom_item: bom_item, status: "PENDING")
      end
    end

    StockReservationJob.perform_later(order)

    order = WorkOrder.includes(*ORDER_INCLUDES).find(order.id)
    render json: WorkOrderSerializer.new(order).serializable_hash, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors(e.record)
  end

  # POST /work-orders/:id/complete
  # Gate: every step must be CERTIFIED. On success the work order transitions to
  # COMPLETE and a CERTIFIED lifecycle event is appended to the assembled unit
  # (the work order's part_instance), whose current_status becomes CERTIFIED.
  def complete
    order = WorkOrder.includes(STEP_INCLUDES).find(params[:id])

    if order.COMPLETE?
      return render_error("Work order is already COMPLETE", "INVALID_STATE", :unprocessable_content)
    end

    uncertified = order.work_order_steps.where.not(status: "CERTIFIED")
    if uncertified.exists?
      return render_error(
        "All steps must be CERTIFIED before the work order can be completed",
        "STEPS_NOT_CERTIFIED",
        :unprocessable_content
      )
    end

    now = Time.current
    instance = order.part_instance
    WorkOrder.transaction do
      order.complete # AASM OPEN/BLOCKED -> COMPLETE
      order.save!

      instance.lifecycle_events.create!(
        event_type: "CERTIFIED",
        actor: "system",
        occurred_at: now,
        recorded_at: now
      )
      instance.update!(current_status: "CERTIFIED")
    end

    order = WorkOrder.includes(*ORDER_INCLUDES).find(order.id)
    render json: WorkOrderSerializer.new(order).serializable_hash
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors(e.record)
  end
end
