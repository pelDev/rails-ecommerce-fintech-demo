class MerchantNotifier
  def self.call(payment, event)
    if Rails.env.development? || Rails.env.test?
      # 1. Immediate UI push for test console
      Turbo::StreamsChannel.broadcast_replace_to(
        "merchant_#{payment.merchant_id}_test_console",
        target: "payment_status_badge",
        partial: "orders/payment_status",
        locals: { payment: payment, event: event }
      )
      Rails.logger.info "Broadcasted payment #{payment.id} event [#{event}] to merchant #{payment.merchant_id}"
    else
        # 2. Production endpoint call (e.g., ActiveJob delivery worker)
        #   WebhookDeliveryJob.perform_later(payment.id, event)
    end
  end
end