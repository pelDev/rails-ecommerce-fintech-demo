class DashboardController < ApplicationController
  # Require authentication for all dashboard actions
  before_action :authenticate_user!

  # Load merchant-specific data
  before_action :load_merchant_data

  # Dashboard main page
  def index
    # Metric cards scoped strictly to current merchant
    @total_volume_cents = @merchant.payments.where(status: 1).sum(:amount_cents) # Succeeded status
    @pending_orders_count = @merchant.orders.where(status: 0).count
    @successful_payments_count = @merchant.payments.where(status: 1).count

    # Recent Data Tables (with eager loading to prevent N+1 queries)
    @recent_orders = @merchant.orders.order(created_at: :desc).limit(5)
    @recent_payments = @merchant.payments.includes(:order).order(created_at: :desc).limit(5)

    # Key status for quick developer check
    @active_api_credential = @merchant.api_credentials.active.first
  end

  private

  def load_merchant_data
    redirect_to new_user_registration_path, alert: "No merchant record found." unless current_user&.merchant
    @merchant = current_user.merchant
  end
end
