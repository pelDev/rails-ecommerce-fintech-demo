class PaymentSerializer
  include ::JSONAPI::Serializer

  # Attributes to expose
  attributes :id, 
             :amount_cents, 
             :currency, 
             :status, 
             :payment_method,
             :provider_reference,
             :idempotency_key,
             :failure_reason,
             :created_at,
             :updated_at

  # Computed attributes
  attribute :amount do |payment|
    payment.amount
  end

  attribute :amount_formatted do |payment|
    payment.amount_formatted
  end

  attribute :status_label do |payment|
    payment.status_label
  end

  attribute :successful do |payment|
    payment.successful?
  end

  attribute :failed do |payment|
    payment.failed?
  end

  attribute :refundable do |payment|
    payment.refundable?
  end

  # Timestamps in human-readable format
  attribute :created_at_formatted do |payment|
    payment.created_at.strftime("%B %d, %Y %I:%M %p %Z")
  end

  attribute :updated_at_formatted do |payment|
    payment.updated_at.strftime("%B %d, %Y %I:%M %p %Z")
  end

  # Status timestamps
  attribute :pending_at do |payment|
    payment.pending_at
  end

  attribute :processing_at do |payment|
    payment.processing_at
  end

  attribute :succeeded_at do |payment|
    payment.succeeded_at
  end

  attribute :failed_at do |payment|
    payment.failed_at
  end

  attribute :refunded_at do |payment|
    payment.refunded_at
  end

  # Conditional attributes for debugging
  attribute :retry_count do |payment|
    payment.retry_count if payment.respond_to?(:retry_count)
  end

  attribute :order_details do |payment|
    order = payment.order
    if order
      {
        id: order.id,
        status: order.status,
        amount: order.total_amount,
        currency: order.currency
      }
    end
  end

  attribute :merchant_details do |payment|
    merchant = payment.merchant
    if merchant
      {
        id: merchant.id,
        name: merchant.name
      }
    end
  end

  # Meta information
  meta do |payment|
    {
      can_refund: payment.refundable?,
      can_retry: payment.respond_to?(:retryable?) && payment.retryable?,
      processing_time: payment.processing_time_in_seconds,
      aasm_state: payment.aasm.current_state,
    }.compact
  end

  # Cache for performance
  cache_options store: Rails.cache, namespace: 'payment_serializer', expires_in: 1.hour
end