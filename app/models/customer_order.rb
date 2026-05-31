class CustomerOrder < ApplicationRecord
  # Minimal stub: the customer_orders table exists (Track 4 demand side), but the
  # full model lands with the customer-order endpoints. This bare class exists so
  # SupplierPurchaseOrder's optional `belongs_to :customer_order` can resolve the
  # constant. Flesh out associations/validations when the demand-side stories land.
end
