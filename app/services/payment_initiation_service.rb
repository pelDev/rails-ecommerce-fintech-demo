class PaymentInitiationService
  # Result object for consistent return values
  class Result
    attr_reader :success, :payment, :error, :error_code, :metadata

    def initialize(success:, payment: nil, error: nil, error_code: nil, metadata: {})
      @success = success
      @payment = payment
      @error = error
      @error_code = error_code
      @metadata = metadata
    end

    def success?
      @success
    end

    def failure?
      !@success
    end

    def to_h
      {
        success: success?,
        payment: payment,
        error: error,
        error_code: error_code,
        metadata: metadata
      }.compact
    end
  end

  # Main entry point
  def initialize(order, params = {})
    @order = order
    @amount = params[:amount] || order.amount_cents
    @currency = params[:currency] || order.currency
    @payment_method = params[:payment_method]
    @idempotency_key = params[:idempotency_key]
    @provider_params = params[:provider_params] || {}
    @metadata = params[:metadata] || {}
    @request_ip = params[:request_ip]
    @user_agent = params[:user_agent]
  end

  def call
    # Validate before anything else
    validation_result = validate!
    return validation_result if validation_result.failure?

    # Check idempotency first (atomic operation)
    idempotency_result = check_idempotency!
    return idempotency_result if idempotency_result.failure?

    # Create payment in a transaction
    payment = nil
    provider_response = nil

    begin
      ActiveRecord::Base.transaction do
        # Create the payment record
        payment = create_payment!

        # Call the payment provider
        provider_response = call_provider(payment)

        # Process the provider response
        process_provider_response!(payment, provider_response)
      end

      # Return success result
      Result.new(
        success: true,
        payment: payment,
        metadata: {
          provider_response: provider_response,
          idempotency_key: @idempotency_key
        }
      )

    rescue ActiveRecord::RecordNotUnique => e
      # This catches any race condition with the idempotency key
      # Check if another payment was already created
      existing_payment = find_existing_payment_by_idempotency_key
      
      if existing_payment
        Result.new(
          success: true,
          payment: existing_payment,
          metadata: {
            duplicate: true,
            idempotency_key: @idempotency_key,
            message: "Payment already initiated with this idempotency key"
          }
        )
      else
        Result.new(
          success: false,
          error: "Concurrent payment initiation detected",
          error_code: "CONCURRENT_PAYMENT",
          metadata: { idempotency_key: @idempotency_key }
        )
      end

    rescue StandardError => e
      # Handle all other errors gracefully
      Rails.logger.error "Payment initiation failed: #{e.message}\n#{e.backtrace.join("\n")}"
      
      Result.new(
        success: false,
        error: e.message,
        error_code: "PAYMENT_INITIATION_ERROR",
        metadata: {
          payment: payment,
          idempotency_key: @idempotency_key,
          error_class: e.class.name
        }
      )
    end
  end

  private

  def validate!
    # Check if order exists and is payable
    unless @order.present?
      return Result.new(
        success: false,
        error: "Order not found",
        error_code: "ORDER_NOT_FOUND"
      )
    end

    # Check if order is in a payable state
    unless order_payable?
      return Result.new(
        success: false,
        error: "Order is not payable",
        error_code: "ORDER_NOT_PAYABLE",
        metadata: { order_status: @order.status }
      )
    end

    # Validate amount matches order
    if @amount != @order.amount_cents
      return Result.new(
        success: false,
        error: "Amount does not match order total",
        error_code: "AMOUNT_MISMATCH",
        metadata: { 
          order_amount: @order.amount_cents, 
          payment_amount: @amount 
        }
      )
    end

    # Validate currency matches order
    if @currency != @order.currency
      return Result.new(
        success: false,
        error: "Currency does not match order currency",
        error_code: "CURRENCY_MISMATCH",
        metadata: { 
          order_currency: @order.currency, 
          payment_currency: @currency 
        }
      )
    end

    # Validate payment method
    unless valid_payment_method?
      return Result.new(
        success: false,
        error: "Invalid payment method",
        error_code: "INVALID_PAYMENT_METHOD",
        metadata: { payment_method: @payment_method }
      )
    end

    # Validate idempotency key if provided
    if @idempotency_key.present? && @idempotency_key.length > 255
      return Result.new(
        success: false,
        error: "Idempotency key too long (max 255 characters)",
        error_code: "IDEMPOTENCY_KEY_TOO_LONG"
      )
    end

    # All validations passed
    Result.new(success: true)
  end

  def order_payable?
    # An order is payable if:
    # 1. It's pending
    # 2. It's not expired
    # 3. It's not already fully paid
    # 4. It's not cancelled or refunded
    
    return false unless @order.pending?
    return false if @order.expired?
    return false if @order.status.in?(['cancelled', 'refunded', 'expired'])
    return false if @order.fully_paid?
    
    true
  end

  def valid_payment_method?
    return false if @payment_method.blank?
    
    # Check against allowed payment methods
    allowed_methods = ['card', 'bank_transfer', 'paypal', 'stripe', 'square']
    allowed_methods.include?(@payment_method)
  end

  def check_idempotency!
    return Result.new(success: true) if @idempotency_key.blank?

    # Check for existing payment with this idempotency key
    existing_payment = find_existing_payment_by_idempotency_key

    if existing_payment
      # Return the existing payment
      return Result.new(
        success: true,
        payment: existing_payment,
        metadata: {
          duplicate: true,
          idempotency_key: @idempotency_key,
          message: "Payment already initiated with this idempotency key"
        }
      )
    end

    Result.new(success: true)
  end

  def find_existing_payment_by_idempotency_key
    return nil if @idempotency_key.blank?
    
    # Scope by merchant to ensure proper isolation
    Payment
      .where(order_id: @order.id, idempotency_key: @idempotency_key)
      .first
  rescue StandardError
    nil
  end

  def create_payment!
    Payment.create!(
      order: @order,
      merchant: @order.merchant,
      amount_cents: @amount,
      currency: @currency,
      payment_method: @payment_method,
      idempotency_key: @idempotency_key,
      status: :created,
      metadata: @metadata.to_json,
      request_ip: @request_ip,
      user_agent: @user_agent
    )
  end

  def call_provider(payment)
    # Use the provider adapter based on the payment method
    # This is where I'd integrate with Stripe, PayPal, etc.
    
    adapter_class = provider_adapter_for(payment.payment_method)
    adapter = adapter_class.new(payment, @provider_params)
    
    adapter.initiate_payment
  rescue => e
    Rails.logger.error "Provider call failed: #{e.message}"
    raise PaymentProviderError, "Provider call failed: #{e.message}"
  end

  def provider_adapter_for(payment_method)
    PaymentProvider::StripeAdapter # Return stripe for everything for now

    # case payment_method.to_s.downcase
    # when 'stripe'
    #   PaymentProvider::StripeAdapter
    # when 'paypal'
    #   PaymentProvider::PaypalAdapter
    # when 'card'
    #   PaymentProvider::CardAdapter
    # when 'bank_transfer'
    #   PaymentProvider::BankTransferAdapter
    # else
    #   raise "Unsupported payment method: #{payment_method}"
    # end
  end

  def process_provider_response!(payment, provider_response)
    case provider_response[:status].to_s
    when 'succeeded'
      # Payment was successful
      payment.succeed_with_reference(provider_response[:provider_reference])
      
      # Log success
      Rails.logger.info "Payment #{payment.id} succeeded with provider reference: #{provider_response[:provider_reference]}"
      
    when 'pending'
      # Payment is pending (e.g., bank transfer)
      payment.mark_pending!
      
      Rails.logger.info "Payment #{payment.id} is pending"
      
    when 'processing'
      # Payment is processing
      payment.processing_with_reference(provider_response[:provider_reference])

      # Schedule a simulated webhook for testing
      if Rails.env.development? || Rails.env.test?
        Rails.logger.info "Scheduling simulated webhook for payment #{payment.id} in 10 seconds"
        StripeWebhookSimulator.schedule_webhook(payment, delay: 10.seconds)
      end
      
      Rails.logger.info "Payment #{payment.id} is processing"
      
    when 'failed'
      # Payment failed
      failure_reason = provider_response[:failure_reason] || 'Payment failed'
      payment.fail_with_reason(failure_reason)
      
      Rails.logger.warn "Payment #{payment.id} failed: #{failure_reason}"
      
      # Raise a specific error for failures
      raise PaymentFailedError, failure_reason
      
    else
      # Unknown status - treat as pending
      payment.mark_pending!
      
      Rails.logger.warn "Unknown provider status: #{provider_response[:status]} for payment #{payment.id}"
    end
  end

  # Custom error classes
  class PaymentProviderError < StandardError; end
  class PaymentFailedError < StandardError; end
end