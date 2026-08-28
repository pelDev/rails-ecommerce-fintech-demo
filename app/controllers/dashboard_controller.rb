class DashboardController < ApplicationController
  # Require authentication for all dashboard actions
  before_action :authenticate_user!

  # Load merchant-specific data
  before_action :load_merchant_data

  # Dashboard main page
  def index
    # Metric cards scoped strictly to current merchant
    @total_volume_cents = @merchant.payments.successful.sum(:amount_cents) # Succeeded status
    @pending_orders_count = @merchant.orders.where(status: :pending).count
    @successful_payments_count = @merchant.payments.successful.count

    # Recent Data Tables (with eager loading to prevent N+1 queries)
    @recent_orders = @merchant.orders.order(created_at: :desc).limit(5)
    @recent_payments = @merchant.payments.includes(:order).order(created_at: :desc).limit(5)
  end
end
