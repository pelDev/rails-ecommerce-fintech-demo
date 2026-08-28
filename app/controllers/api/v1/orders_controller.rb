class Api::V1::OrdersController < Api::V1::BaseController
    # Public endpoint skip authentication
    skip_before_action :authenticate_api_credential!, only: [:ping]

    def index
        orders = current_merchant.orders
        render json: orders
    end

    def create
        @order_form = OrderCreationForm.new(
            merchant: current_merchant,
            currency: order_params[:currency],
            external_reference: order_params[:external_reference],
            order_items_attributes: order_params[:order_items_attributes] || []
        )

        if @order_form.save
            render json: {
                success: true,
                order: @order_form.order.as_json(include: :order_items)
            }, status: :created
        else
            render json: {
                success: false,
                errors: @order_form.errors.full_messages
            }, status: :unprocessable_entity
        end
    end

    def ping
        render json: { status: "ok" }
    end

    def order_params
        params.require(:order).permit(:currency, :external_reference, order_items_attributes: [:product_name, :quantity, :unit_price_cents])
    end
end
