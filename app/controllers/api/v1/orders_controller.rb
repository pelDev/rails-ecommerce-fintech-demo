class Api::V1::OrdersController < Api::V1::BaseController
    # Public endpoint skip authentication
    skip_before_action :authenticate_api_credential!, only: [:ping]

    def index
        orders = current_merchant.orders
        render json: orders
    end

    def ping
        render json: { status: "ok" }
    end
end
