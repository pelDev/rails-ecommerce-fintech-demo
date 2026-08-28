class StripeWebhookSimulator
  # This service simulates webhook callbacks from payment providers
  # after a delay, mimicking real-world webhook behavior
  
  def self.schedule_webhook(payment, delay: 10.seconds)
    # Schedule a simulated webhook call after the delay
    # This runs in the background using Rails' async job system
    
    WebhookSimulationJob.set(wait: delay).perform_later(payment.id)
  end

  def self.trigger_webhook(payment_id, status: nil)
    payment = Payment.find(payment_id)
    return unless payment
    
    # Determine outcome if not specified
    status ||= determine_outcome
    
    # Generate webhook payload
    payload = generate_webhook_payload(payment, status)
    
    # Send to webhook controller (simulate external call)
    send_webhook_request(payment, payload, status)
  end

  private

  def self.determine_outcome
    # Randomly determine success or failure
    # 80% success rate for realistic testing
    rand < 0.8 ? 'succeeded' : 'failed'
  end

  def self.generate_webhook_payload(payment, status)
    # Generate a realistic webhook payload similar to what Stripe would send
    {
      id: payment.provider_reference || "pi_#{SecureRandom.hex(16)}",
      object: 'payment_intent',
      status: status,
      amount: payment.amount_cents,
      currency: payment.currency,
      payment_method: payment.payment_method,
      created_at: Time.current.to_i,
      merchant_id: payment.merchant_id,
      order_id: payment.order_id,
      
      # Additional fields based on status
      charges: {
        data: [
          {
            id: "ch_#{SecureRandom.hex(16)}",
            amount: payment.amount_cents,
            currency: payment.currency,
            status: status == 'succeeded' ? 'succeeded' : 'failed',
            payment_method_details: {
              card: {
                brand: 'visa',
                last4: '4242',
                exp_month: 12,
                exp_year: 2025
              }
            }
          }
        ]
      },
      
      # Failure details if applicable
      last_payment_error: status == 'failed' ? {
        type: 'card_declined',
        code: 'card_declined',
        message: 'Your card was declined.',
        decline_code: 'generic_decline'
      } : nil
    }.deep_stringify_keys
  end

  def self.send_webhook_request(payment, payload, status)
    # This simulates Stripe calling your webhook endpoint
    # In production, Stripe would call your endpoint with the payload
    
    # Store the event ID for deduplication
    event_id = "evt_#{SecureRandom.hex(16)}"
    event_type = status == 'succeeded' ? 'payment_intent.succeeded' : 'payment_intent.payment_failed'
    
    # Create the webhook event
    webhook_event = WebhookEvent.create!(
      provider_event_id: event_id,
      payload: {
        id: event_id,
        type: event_type,
        data: payload,
        created: Time.current.to_i
      },
      signature: 'simulated_signature',
      event_type: event_type,
      provider: 'stripe',
      source_ip: '127.0.0.1',
      user_agent: 'Stripe-Webhook/1.0'
    )
    
    # Process the webhook
    WebhookProcessor.process(webhook_event)
  end
end