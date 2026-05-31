class PartsController < ApplicationController
  def index
    scope = PartDefinition.all
    scope = scope.by_status(params[:status]) if params[:status].present?
    scope = scope.search(params[:search]) if params[:search].present?
    scope = scope.order(:part_number)

    @pagy, parts = pagy(:offset, scope)

    render json: {
      data: PartDefinitionSerializer.new(parts).serializable_hash,
      meta: pagination_meta(@pagy)
    }
  end

  def show
    part = find_part!
    render json: PartDefinitionSerializer.new(part).serializable_hash
  end

  def create
    part = PartDefinition.new(create_params)

    if part.save
      render json: PartDefinitionSerializer.new(part).serializable_hash, status: :created
    else
      render_validation_errors(part)
    end
  end

  def update
    part = find_part!

    if revision_locked?(part)
      return render_error("Revision cannot be changed on a non-draft part", "REVISION_LOCKED", :unprocessable_content)
    end

    if part.update(update_params)
      render json: PartDefinitionSerializer.new(part).serializable_hash
    else
      render_validation_errors(part)
    end
  end

  def instances
    find_part!

    scope = PartInstance.includes(:part_definition).for_part_number(params[:part_number])
    scope = scope.with_status(params[:status]) if params[:status].present?
    scope = scope.order(:serial_number)

    @pagy, instances = pagy(:offset, scope)

    render json: {
      data: PartInstanceSerializer.new(instances).serializable_hash,
      meta: pagination_meta(@pagy)
    }
  end

  def update_status
    part = find_part!
    target = params[:status].to_s
    event = STATUS_EVENTS[target]

    if event.nil? || !part.public_send("may_#{event}?")
      return render_error(
        "Cannot transition from #{part.status} to #{target.presence || 'nil'}",
        "INVALID_TRANSITION",
        :unprocessable_content
      )
    end

    part.public_send("#{event}!")
    render json: PartDefinitionSerializer.new(part).serializable_hash
  end

  private

  STATUS_EVENTS = {
    "RELEASED" => :release,
    "OBSOLETE" => :obsolete
  }.freeze

  def find_part!
    PartDefinition.find_by!(part_number: params[:part_number])
  end

  def revision_locked?(part)
    params.key?(:revision) && part.status != "DRAFT"
  end

  def create_params
    params.permit(:part_number, :name, :description, :revision)
  end

  def update_params
    params.permit(:name, :description, :revision)
  end
end
