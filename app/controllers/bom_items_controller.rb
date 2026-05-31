class BomItemsController < ApplicationController
  def index
    part = find_part!
    items = part.bom_items.includes(:child, prerequisite_links: { prerequisite: :child }).order(:created_at)

    render json: { data: BomItemSerializer.new(items).serializable_hash }
  end

  def create
    part = find_part!

    unless part.status == "DRAFT"
      return render_error("BOM is locked once the part is released", "PART_NOT_DRAFT", :unprocessable_content)
    end

    child = PartDefinition.find_by(part_number: params[:childPartNumber])
    unless child
      return render_error("Child part not found", "CHILD_NOT_FOUND", :unprocessable_content)
    end

    item = nil
    BomItem.transaction do
      item = part.bom_items.create!(child: child, quantity: params[:quantity])
      Array(params[:prerequisites]).each do |prerequisite_id|
        item.prerequisite_links.create!(prerequisite_bom_item_id: prerequisite_id)
      end
    end

    render json: serialize(item), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors(e.record)
  end

  def destroy
    part = find_part!
    item = part.bom_items.find(params[:bom_item_id])
    item.update!(deleted_at: Time.current)

    render json: serialize(item)
  end

  private

  def find_part!
    PartDefinition.find_by!(part_number: params[:part_number])
  end

  def serialize(item)
    BomItemSerializer.new(item).serializable_hash
  end
end
