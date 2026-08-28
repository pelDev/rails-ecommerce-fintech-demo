class WebhookSimulationJob < ApplicationJob
  queue_as :webhooks

  def perform(payment_id)
    payment = Payment.find_by(id: payment_id)
    return unless payment
    
    Rails.logger.info "Processing simulated webhook for payment #{payment_id}"
    
    # Trigger the webhook with a random outcome
    StripeWebhookSimulator.trigger_webhook(payment_id)
  end
end
