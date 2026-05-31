class CustomerOrdersController < ApplicationController
  def index
    scope = CustomerOrder
      .includes(customer_order_lines: :part_definition)
      .order(created_at: :desc)

    @pagy, orders = pagy(:offset, scope)

    render json: {
      data: CustomerOrderSerializer.new(orders).serializable_hash,
      meta: pagination_meta(@pagy)
    }
  end

  def show
    order = CustomerOrder
      .includes(customer_order_lines: :part_definition)
      .find(params[:id])

    render json: CustomerOrderSerializer.new(order).serializable_hash
  end

  # POST /customer-orders
  #
  # Creates an OPEN customer order plus a line per `lines` entry, then enqueues a
  # BomExplosionJob per line. The explosion (stock reservation / supplier PO / work
  # order creation) runs async (JAS-42) so the order returns immediately. Validate
  # everything up front (422 before any writes); the create is wrapped in a
  # transaction and jobs are enqueued only after it commits.
  def create
    customer_name = params[:customerName]
    lines = params[:lines]

    if customer_name.blank?
      return render_error("customerName can't be blank", "VALIDATION_FAILED", :unprocessable_content)
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

    order = CustomerOrder.new(customer_name: customer_name, status: "OPEN")

    CustomerOrder.transaction do
      order.save!
      lines.each do |line|
        order.customer_order_lines.create!(
          part_definition: parts_by_number.fetch(line[:partNumber]),
          quantity: line[:quantity]
        )
      end
    end

    order.customer_order_lines.each { |line| BomExplosionJob.perform_later(line) }

    order = CustomerOrder
      .includes(customer_order_lines: :part_definition)
      .find(order.id)

    render json: CustomerOrderSerializer.new(order).serializable_hash, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors(e.record)
  end
end
