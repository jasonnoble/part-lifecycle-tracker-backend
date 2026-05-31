require "rails_helper"

RSpec.describe StockReservationJob, type: :job do
  subject(:run) { described_class.new.perform(work_order) }

  let(:part) { create(:part_definition) }
  let(:bom_item) { create(:bom_item, child: part) }
  let(:work_order) { create(:work_order) }

  def reason_for(step)
    "Reserved for work order step #{step.id}"
  end

  describe "#perform" do
    context "when stock is available" do
      let!(:stock) { create(:stock, part_definition: part, quantity_on_hand: 5, quantity_reserved: 0) }
      let!(:step) { create(:work_order_step, work_order:, bom_item:, status: "PENDING") }

      it "increments quantity_reserved and leaves the step PENDING" do
        run

        expect(stock.reload.quantity_reserved).to eq(1)
        expect(step.reload.status).to eq("PENDING")
      end

      it "writes a StockAuditLog describing the reservation" do
        expect { run }.to change(StockAuditLog, :count).by(1)

        log = StockAuditLog.last
        expect(log.part_definition_id).to eq(part.id)
        expect(log.change_amount).to eq(-1)
        expect(log.reason).to eq(reason_for(step))
      end

      it "leaves the work order OPEN" do
        run
        expect(work_order.reload.status).to eq("OPEN")
      end
    end

    context "when stock is insufficient" do
      let!(:stock) { create(:stock, part_definition: part, quantity_on_hand: 1, quantity_reserved: 1) }
      let!(:step) { create(:work_order_step, work_order:, bom_item:, status: "PENDING") }

      it "blocks the step" do
        run
        expect(step.reload.status).to eq("BLOCKED")
      end

      it "does not change quantity_reserved" do
        run
        expect(stock.reload.quantity_reserved).to eq(1)
      end

      it "does not write a StockAuditLog" do
        expect { run }.not_to change(StockAuditLog, :count)
      end

      it "blocks the work order" do
        run
        expect(work_order.reload.status).to eq("BLOCKED")
      end
    end

    context "when there is no stock row for the part" do
      let!(:step) { create(:work_order_step, work_order:, bom_item:, status: "PENDING") }

      it "blocks the step (available is zero)" do
        run
        expect(step.reload.status).to eq("BLOCKED")
        expect(work_order.reload.status).to eq("BLOCKED")
      end
    end

    context "idempotency" do
      let!(:stock) { create(:stock, part_definition: part, quantity_on_hand: 5, quantity_reserved: 0) }
      let!(:step) { create(:work_order_step, work_order:, bom_item:, status: "PENDING") }

      it "does not double-reserve when run twice" do
        run
        expect(stock.reload.quantity_reserved).to eq(1)

        expect { described_class.new.perform(work_order) }
          .not_to change { stock.reload.quantity_reserved }

        expect(stock.reload.quantity_reserved).to eq(1)
        expect(StockAuditLog.where(reason: reason_for(step)).count).to eq(1)
      end
    end

    context "partial availability across multiple steps" do
      let(:other_part) { create(:part_definition) }
      let(:other_bom_item) { create(:bom_item, child: other_part) }

      let!(:available_stock) { create(:stock, part_definition: part, quantity_on_hand: 3, quantity_reserved: 0) }
      let!(:depleted_stock) { create(:stock, part_definition: other_part, quantity_on_hand: 0, quantity_reserved: 0) }

      let!(:available_step) { create(:work_order_step, work_order:, bom_item:, status: "PENDING") }
      let!(:blocked_step) { create(:work_order_step, work_order:, bom_item: other_bom_item, status: "PENDING") }

      it "reserves the available line and blocks the unavailable line" do
        run

        expect(available_step.reload.status).to eq("PENDING")
        expect(available_stock.reload.quantity_reserved).to eq(1)

        expect(blocked_step.reload.status).to eq("BLOCKED")
        expect(depleted_stock.reload.quantity_reserved).to eq(0)
      end

      it "blocks the work order because at least one step is blocked" do
        run
        expect(work_order.reload.status).to eq("BLOCKED")
      end
    end
  end
end
