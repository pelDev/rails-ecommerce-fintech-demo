class Api::V1::PaymentsController < Api::V1::BaseController
    before_action :find_order

    def create
      result = PaymentInitiationService.new(
        @order,
        payment_params
      ).call

      if result.success?
        render json: {
          success: true,
          payment: PaymentSerializer.new(result.payment).serializable_hash,
          metadata: result.metadata
        }, status: :created
      else
        render json: {
          success: false,
          error: result.error,
          error_code: result.error_code,
          metadata: result.metadata
        }, status: :unprocessable_entity
      end
    end
    
    private

    def find_order
        @order = current_user.merchant.orders.find(params[:order_id])
    rescue ActiveRecord::RecordNotFound
        render json: { error: 'Order not found' }, status: :not_found
    end

    def payment_params
        {
          amount: params[:amount],
          currency: params[:currency],
          payment_method: params[:payment_method],
          idempotency_key: params[:idempotency_key],
          provider_params: params[:provider_params] || {},
          metadata: params[:metadata] || {},
          request_ip: request.remote_ip,
          user_agent: request.user_agent
        }
    end
end
