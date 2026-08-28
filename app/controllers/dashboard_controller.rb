class DashboardController < ApplicationController
  # Require authentication for all dashboard actions
  before_action :authenticate_user!

  # Load merchant-specific data
  before_action :load_merchant_data, only: [ :index, :analytics, :recent_orders, :payment_metrics ]

  # Dashboard main page
  def index
    # @merchant is loaded by load_merchant_data
  end

  # Analytics page
  def analytics
    @revenue_by_day
  end

  private

  def load_merchant_data
    # Ensure user belongs to a merchant
    unless current_user.merchant
      redirect_to onboarding_path, alert: "Please set up your merchant profile first"
      return
    end

    @merchant = current_user.merchant
    @user = current_user
  end
end
