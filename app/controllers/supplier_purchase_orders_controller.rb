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

  # POST /supplier-purchase-orders/:id/receive
  #
  # Atomic receive: validate everything up front (422 before any writes), then
  # in ONE transaction create a PartInstance + initial RECEIVED LifecycleEvent
  # per serial, bump stock.quantity_on_hand (row-locked), write a StockAuditLog,
  # advance each line's status via AASM, and roll up the PO status. Any failure
  # rolls back the whole shipment — partial physical state is worse than none.
  def receive
    order = SupplierPurchaseOrder
      .includes(supplier_purchase_order_lines: :part_definition)
      .find(params[:id])

    requested = params[:lines]
    unless requested.is_a?(Array) && requested.present?
      return render_error("lines must include at least one line item", "VALIDATION_FAILED", :unprocessable_content)
    end

    lines_by_id = order.supplier_purchase_order_lines.index_by { |l| l.id }
    all_serials = []

    requested.each do |req|
      line = lines_by_id[req[:lineId]]
      if line.nil?
        return render_error("lineId #{req[:lineId]} does not belong to this purchase order", "VALIDATION_FAILED", :unprocessable_content)
      end

      quantity = req[:quantity].to_i
      serials = Array(req[:serials])

      if quantity <= 0
        return render_error("quantity must be greater than 0", "VALIDATION_FAILED", :unprocessable_content)
      end

      if serials.any? { |s| s.to_s.strip.empty? }
        return render_error("serials must all be non-blank", "VALIDATION_FAILED", :unprocessable_content)
      end

      if serials.length != quantity
        return render_error("serials count (#{serials.length}) must equal quantity (#{quantity})", "VALIDATION_FAILED", :unprocessable_content)
      end

      all_serials.concat(serials)
    end

    if all_serials.uniq.length != all_serials.length
      return render_error("serials must be unique within the request", "VALIDATION_FAILED", :unprocessable_content)
    end

    existing = PartInstance.where(serial_number: all_serials).pluck(:serial_number)
    if existing.any?
      return render_error("serials already in use: #{existing.join(', ')}", "VALIDATION_FAILED", :unprocessable_content)
    end

    SupplierPurchaseOrder.transaction do
      requested.each do |req|
        line = lines_by_id[req[:lineId]]
        quantity = req[:quantity].to_i
        serials = Array(req[:serials])
        part = line.part_definition

        serials.each do |serial|
          instance = part.part_instances.create!(serial_number: serial, current_status: "RECEIVED")
          instance.lifecycle_events.create!(
            event_type: "RECEIVED",
            actor: "system/receive",
            occurred_at: Time.current,
            recorded_at: Time.current
          )
        end

        stock = Stock.lock.find_or_create_by!(part_definition: part)
        stock.update!(quantity_on_hand: stock.quantity_on_hand + quantity)

        StockAuditLog.create!(
          part_definition: part,
          change_amount: quantity,
          reason: "PO receive #{order.id}"
        )

        line.update!(quantity_received: line.quantity_received + quantity)
        advance_line_status!(line)
      end

      advance_order_status!(order)
    end

    order = SupplierPurchaseOrder
      .includes(supplier_purchase_order_lines: :part_definition)
      .find(order.id)

    render json: SupplierPurchaseOrderSerializer.new(order).serializable_hash, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors(e.record)
  end

  private

  def advance_line_status!(line)
    event = line.quantity_received >= line.quantity ? :receive : :partially_receive
    unless line.send("#{event}!")
      raise ActiveRecord::RecordInvalid, line
    end
  end

  def advance_order_status!(order)
    lines = order.supplier_purchase_order_lines.reload
    event = lines.all? { |l| l.status == "RECEIVED" } ? :receive : :partially_receive
    unless order.send("#{event}!")
      raise ActiveRecord::RecordInvalid, order
    end
  end
end
