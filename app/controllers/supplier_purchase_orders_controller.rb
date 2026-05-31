class SupplierPurchaseOrdersController < ApplicationController
  def index
    scope = SupplierPurchaseOrder
      .includes(supplier_purchase_order_lines: :part_definition)
      .order(created_at: :desc)

    @pagy, orders = pagy(:offset, scope)

    render json: {
      data: SupplierPurchaseOrderSerializer.new(orders).serializable_hash,
      meta: pagination_meta(@pagy)
    }
  end

  def show
    order = SupplierPurchaseOrder
      .includes(supplier_purchase_order_lines: :part_definition)
      .find(params[:id])

    render json: SupplierPurchaseOrderSerializer.new(order).serializable_hash
  end

  def create
    supplier_id = params[:supplierId]
    lines = params[:lines]

    if supplier_id.blank?
      return render_error("supplierId can't be blank", "VALIDATION_FAILED", :unprocessable_content)
    end

    unless lines.is_a?(Array) && lines.present?
      return render_error("lines must include at least one line item", "VALIDATION_FAILED", :unprocessable_content)
    end

    part_numbers = lines.map { |line| line[:partNumber] }
    parts_by_number = PartDefinition.where(part_number: part_numbers).index_by(&:part_number)

    missing = part_numbers.reject { |pn| parts_by_number.key?(pn) }
    if missing.any?
      return render_error("Unknown partNumber: #{missing.uniq.join(', ')}", "VALIDATION_FAILED", :unprocessable_content)
    end

    order = SupplierPurchaseOrder.new(supplier_id: supplier_id, status: "OPEN")

    SupplierPurchaseOrder.transaction do
      order.save!
      lines.each do |line|
        order.supplier_purchase_order_lines.create!(
          part_definition: parts_by_number.fetch(line[:partNumber]),
          quantity: line[:quantity],
          quantity_received: 0,
          status: "NEEDS_ORDERING"
        )
      end
    end

    order = SupplierPurchaseOrder
      .includes(supplier_purchase_order_lines: :part_definition)
      .find(order.id)

    render json: SupplierPurchaseOrderSerializer.new(order).serializable_hash, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors(e.record)
  end
end
