class WorkOrderStepsController < ApplicationController
  STEP_INCLUDES = { work_order_steps: { bom_item: :child } }.freeze
  ORDER_INCLUDES = [ :part_definition, :part_instance, STEP_INCLUDES ].freeze

  # POST /work-orders/:id/steps/:step_id/install
  # Body: { "installedSerial": "..." } — the actor is the authenticated user,
  # and installing is the installers' job.
  def install
    step = find_step!

    unless step.PENDING?
      return render_error("Step is not PENDING (current: #{step.status})", "INVALID_STEP_STATE", :conflict)
    end

    unless Permissions.can?(current_user, "step.install")
      return render_error(
        "#{current_user.email} is not authorized to install (installer role required)",
        "FORBIDDEN",
        :forbidden
      )
    end

    blocking = uncertified_prerequisite(step)
    if blocking
      return render_error(
        "Prerequisite #{blocking} must be CERTIFIED before this step can be installed",
        "DEPENDENCY_NOT_MET",
        :conflict
      )
    end

    instance = PartInstance.find_by(serial_number: params[:installedSerial])
    if instance.nil?
      return render_error("Unknown installedSerial: #{params[:installedSerial]}", "VALIDATION_FAILED", :unprocessable_content)
    end

    now = Time.current
    WorkOrderStep.transaction do
      step.installed_part_instance = instance
      step.installed_actor = current_user.email
      step.installed_at = now
      step.install # AASM PENDING -> INSTALLED
      step.save!

      instance.lifecycle_events.create!(
        event_type: "INSTALLED",
        actor: current_user.email,
        occurred_at: now,
        recorded_at: now
      )
      instance.update!(current_status: "INSTALLED")
    end

    render_order(step.work_order_id)
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors(e.record)
  end

  # POST /work-orders/:id/steps/:step_id/validate
  # The actor is the authenticated user; validating is also installer work —
  # four-eyes requires a *different* installer, not a different role.
  def validate_step
    step = find_step!

    unless step.INSTALLED?
      return render_error("Step is not INSTALLED (current: #{step.status})", "INVALID_STEP_STATE", :conflict)
    end

    unless Permissions.can?(current_user, "step.validate")
      return render_error(
        "#{current_user.email} is not authorized to validate (installer role required)",
        "FORBIDDEN",
        :forbidden
      )
    end

    # Four-eyes: the validator must differ from the installer — an identity
    # rule on the authenticated user, not a role rule (two installers are fine).
    # Checked here BEFORE writing; the work_order_steps_four_eyes DB CHECK is
    # the backstop.
    if current_user.email == step.installed_actor
      return render_error(
        "Validator must differ from the installer (#{step.installed_actor})",
        "SAME_ACTOR",
        :conflict
      )
    end

    step.validated_actor = current_user.email
    step.validated_at = Time.current
    step.validate_step # AASM INSTALLED -> VALIDATED
    step.save!

    render_order(step.work_order_id)
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors(e.record)
  end

  # POST /work-orders/:id/steps/:step_id/certify
  # The actor is the authenticated user; certification requires the assigned
  # qa_engineer role (never client-supplied — see JAS-75/JAS-79).
  def certify
    step = find_step!

    unless step.VALIDATED?
      return render_error("Step is not VALIDATED (current: #{step.status})", "INVALID_STEP_STATE", :conflict)
    end

    unless Permissions.can?(current_user, "step.certify")
      return render_error(
        "#{current_user.email} is not authorized to certify (qa_engineer role required)",
        "FORBIDDEN",
        :forbidden
      )
    end

    step.certified_actor = current_user.email
    step.certified_at = Time.current
    step.certify # AASM VALIDATED -> CERTIFIED
    step.save!

    render_order(step.work_order_id)
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors(e.record)
  end

  private

  def find_step!
    work_order = WorkOrder.find(params[:id])
    work_order.work_order_steps.find(params[:step_id])
  end

  # Returns the child part_number of a prerequisite step that is not yet CERTIFIED,
  # or nil if all prerequisites are met. This is the muzzle-before-dome rule.
  def uncertified_prerequisite(step)
    prerequisite_bom_item_ids = step.bom_item.prerequisites.pluck(:id)
    return nil if prerequisite_bom_item_ids.empty?

    blocking_step = step.work_order.work_order_steps
      .where(bom_item_id: prerequisite_bom_item_ids)
      .where.not(status: "CERTIFIED")
      .includes(bom_item: :child)
      .first

    blocking_step&.bom_item&.child&.part_number
  end

  def render_order(work_order_id)
    order = WorkOrder.includes(*ORDER_INCLUDES).find(work_order_id)
    render json: WorkOrderSerializer.new(order).serializable_hash
  end
end
