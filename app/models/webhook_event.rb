class WebhookEvent < ApplicationRecord
  # Constants
  MAX_RETRIES = 3
  RETRY_DELAY = 5.minutes

  # Enums
  enum :processing_status, {
    pending: 0,
    processing: 1,
    completed: 2,
    failed: 3
  }, prefix: true, scopes: true

  # Validations
  validates :provider_event_id, presence: true, 
                                uniqueness: true,
                                length: { maximum: 255 }
  validates :payload, presence: true
  validates :signature, presence: true, length: { maximum: 255 }
  validates :processing_status, presence: true, 
                                inclusion: { in: processing_statuses.keys }
  validates :retry_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Scopes
  scope :unprocessed, -> { where(processed_at: nil) }
  scope :processed, -> { where.not(processed_at: nil) }
  scope :failed, -> { where(processing_status: :failed) }
  scope :pending_processing, -> { where(processing_status: :pending) }
  scope :in_progress, -> { where(processing_status: :processing) }
  scope :completed_successfully, -> { where(processing_status: :completed) }
  scope :by_event_type, ->(type) { where(event_type: type) }
  scope :by_provider, ->(provider) { where(provider: provider) }
  scope :by_date_range, ->(start, finish) { where(created_at: start..finish) }
  scope :recent, ->(limit = 100) { order(created_at: :desc).limit(limit) }
  scope :failed_retryable, -> { 
    failed.where('retry_count < ? AND failed_at < ?', MAX_RETRIES, RETRY_DELAY.ago)
  }

  # Callbacks
  before_validation :normalize_fields
  after_create :log_webhook_received
  after_update :log_status_change, if: -> { saved_change_to_processing_status? }

  # Instance methods
  def processed?
    processed_at.present?
  end

  def completed?
    processing_status == 'completed'
  end

  def failed?
    processing_status == 'failed'
  end

  def retryable?
    failed? && retry_count < MAX_RETRIES
  end

  def mark_as_processing!
    update!(processing_status: :processing, processed_at: Time.current)
  end

  def mark_as_completed!
    update!(processing_status: :completed, processed_at: Time.current)
  end

  def mark_as_failed!(error_message)
    update!(
      processing_status: :failed,
      failed_at: Time.current,
      processing_error: error_message,
      retry_count: retry_count + 1
    )
  end

  def process!
    # This is the atomic processing pattern
    return false if processed? || completed?
    
    transaction do
      # Mark as processing to prevent race conditions
      mark_as_processing!
      
      begin
        # Process the webhook payload
        process_payload!
        mark_as_completed!
      rescue => e
        mark_as_failed!(e.message)
        raise e if retry_count >= MAX_RETRIES
        # Queue for retry
        WebhookEventJob.set(wait: RETRY_DELAY).perform_later(id)
      end
    end
  end

  def payload_data
    payload.is_a?(Hash) ? payload : JSON.parse(payload)
  rescue JSON::ParserError
    {}
  end

  # Class methods
  class << self
    def find_or_process(provider_event_id, payload, signature)
      # This is the main entry point for webhook processing
      # The unique constraint ensures exactly-once processing

      begin
        # Try to create - will raise if duplicate
        webhook = create!(
          provider_event_id: provider_event_id,
          payload: payload,
          signature: signature,
          event_type: payload[ 'type' ],
          provider: payload[ 'provider' ],
          source_ip: Thread.current[:request_ip],
          user_agent: Thread.current[:user_agent]
        )

        # New webhook - process it
        webhook.process!
        { webhook: webhook, new: true }

      rescue ActiveRecord::RecordNotUnique
        # Duplicate webhook - already processed or processing
        webhook = find_by(provider_event_id: provider_event_id)
        { webhook: webhook, new: false, duplicate: true }
      end
    end

    def retry_failed
      failed_retryable.find_each do |webhook|
        WebhookEventJob.perform_later(webhook.id)
      end
    end

    def cleanup_old_events(days = 30)
      where('created_at < ?', days.days.ago).where(processing_status: :completed).delete_all
    end

    def success_rate(days = 7)
      total = where('created_at > ?', days.days.ago).count
      return 0 if total.zero?
      
      successful = completed_successfully.where('created_at > ?', days.days.ago).count
      (successful.to_f / total * 100).round(2)
    end

    def average_processing_time(days = 7)
      completed_successfully
        .where('created_at > ?', days.days.ago)
        .where.not(processed_at: nil)
        .pluck(:created_at, :processed_at)
        .map { |created, processed| processed - created }
        .then { |times| times.present? ? (times.sum / times.length) : nil }
    end
  end

  private

  def normalize_fields
    self.provider_event_id = provider_event_id.strip if provider_event_id.present?
    self.event_type = event_type.strip.downcase if event_type.present?
    self.provider = provider.strip.downcase if provider.present?
  end

  def log_webhook_received
    Rails.logger.info "Webhook received: provider_event_id=#{provider_event_id}, event_type=#{event_type}"
  end

  def log_status_change
    Rails.logger.info "Webhook #{provider_event_id} status changed: #{status_was} -> #{processing_status}"
  end

  def process_payload!
    # Override this method in subclasses or use a service
    # This is where the actual webhook processing logic goes
    case event_type
    when 'payment.succeeded'
      process_payment_succeeded
    when 'payment.failed'
      process_payment_failed
    when 'refund.succeeded'
      process_refund_succeeded
    else
      # Default: store but don't process unknown events
      Rails.logger.warn "Unknown webhook event type: #{event_type}"
    end
  end

  def process_payment_succeeded
    # Find and update the payment
    # This would be implemented with your actual business logic
    payment = Payment.find_by(provider_reference: payload_data['payment_id'])
    return unless payment

    if payment.status_pending? || payment.status_processing?
      payment.mark_as_completed!(payload_data['transaction_id'])
    end
  end

  def process_payment_failed
    payment = Payment.find_by(provider_reference: payload_data['payment_id'])
    return unless payment

    if payment.status_pending? || payment.status_processing?
      payment.mark_as_failed!(payload_data['failure_reason'])
    end
  end

  def process_refund_succeeded
    payment = Payment.find_by(provider_reference: payload_data['payment_id'])
    return unless payment

    if payment.status_completed? && !payment.refunded?
      payment.refund!
    end
  end
end
