class WebhookProcessor
  # This service processes webhook events with exactly-once semantics
  
  def self.process(webhook_event)
    # Check if already processed
    if webhook_event.processed?
      Rails.logger.info "Webhook #{webhook_event.provider_event_id} already processed"
      return true
    end
    
    # Mark as processing
    webhook_event.mark_as_processing!
    
    begin
      # Determine the event type and process accordingly
      result = case webhook_event.event_type
      when 'payment_intent.succeeded'
        process_payment_success(webhook_event)
      when 'payment_intent.payment_failed'
        process_payment_failure(webhook_event)
      when 'refund.succeeded'
        process_refund_success(webhook_event)
      else
        Rails.logger.warn "Unknown webhook event type: #{webhook_event.event_type}"
        webhook_event.mark_as_completed!
        true
      end
      
      if result
        webhook_event.mark_as_completed!
      else
        webhook_event.mark_as_failed!('Processing failed')
        false
      end
      
    rescue => e
      Rails.logger.error "Webhook processing error: #{e.message}"
      if Rails.env.development?
        Rails.logger.error e.backtrace.join("\n")
      end
      webhook_event.mark_as_failed!(e.message)
      false
    end
  end

  private

  def self.process_payment_success(webhook_event)
    payment_id = webhook_event.payload_data.dig('data', 'id')
    return false unless payment_id
    
    # Find the payment by provider reference
    payment = Payment.find_by(provider_reference: payment_id)
    return false unless payment
    
    # Update payment status
    payment.succeed!
    
    Rails.logger.info "Payment #{payment.id} succeeded via webhook"
    true
  end

  def self.process_payment_failure(webhook_event)
    payment_id = webhook_event.payload_data.dig('data', 'id')
    return false unless payment_id
    
    # Find the payment by provider reference
    payment = Payment.find_by(provider_reference: payment_id)
    return false unless payment
    
    # Get failure reason
    error_data = webhook_event.payload_data.dig('data', 'last_payment_error')
    failure_reason = error_data&.dig('message') || 'Payment failed'
    
    # Update payment status
    payment.fail_with_reason(failure_reason)
    
    Rails.logger.info "Payment #{payment.id} failed via webhook: #{failure_reason}"
    true
  end

  def self.process_refund_success(webhook_event)
    payment_id = webhook_event.payload_data.dig('data', 'payment_intent')
    return false unless payment_id
    
    # Find the payment by provider reference
    payment = Payment.find_by(provider_reference: payment_id)
    return false unless payment
    
    # Update payment status
    payment.refund!
    
    Rails.logger.info "Payment #{payment.id} refunded via webhook"
    true
  end
end