class Payment < ApplicationRecord
  include AASM

  # Constants
  CURRENCIES = %w[USD EUR GBP JPY CAD AUD CHF CNY HKD NZD SEK KRW SGD NOK MXN INR BRL ZAR TRY RUB].freeze
  MINIMUM_AMOUNT = 1
  MAXIMUM_AMOUNT = 999_999_999

  # Associations
  belongs_to :order
  belongs_to :merchant

  # Validations
  validates :order, presence: true
  validates :merchant, presence: true
  validates :amount_cents, presence: true,
                           numericality: {
                             only_integer: true,
                             greater_than: 0,
                             less_than_or_equal_to: MAXIMUM_AMOUNT
                           }
  validates :currency, presence: true,
                       inclusion: { in: CURRENCIES }
  validates :idempotency_key, uniqueness: {
                                scope: :order_id,
                                message: "already used for this order"
                              },
                              allow_nil: true,
                              length: { maximum: 255 }
  validates :provider_reference, uniqueness: true,
                                 allow_nil: true,
                                 length: { maximum: 255 }
  validates :failure_reason, length: { maximum: 500 },
                             allow_nil: true

  # Custom validations
  validate :amount_matches_order_total, if: -> { order.present? }
  validate :validate_payment_method, if: -> { payment_method.present? }
  validate :validate_card_details, if: -> { payment_method == "card" }

  # AASM State Machine
  aasm column: :status do
    # States
    state :created, initial: true
    state :pending
    state :processing
    state :succeeded
    state :failed
    state :refunded

    # Events
    event :mark_pending do
      # Guard: Only created payments can become pending
      guards :can_mark_pending?

      before do
        self.pending_at = Time.current
      end

      transitions from: :created, to: :pending
    end

    event :mark_processing do
      # Guard: Only pending payments can be processed
      guards :can_mark_processing?

      before do
        self.processing_at = Time.current
      end

      after do
        # Notify merchant that payment is processing
        notify_merchant(:processing)
      end

      transitions from: [ :created, :pending ], to: :processing
    end

    event :succeed do
      # Guard: Only processing payments can succeed
      guards :can_succeed?

      before do
        self.succeeded_at = Time.current
        self.provider_reference = @provider_reference if @provider_reference
      end

      after do
        # Update order status
        order.mark_paid! if order.may_mark_paid?
        # Send success notification
        notify_merchant(:success)
        # Log success
        log_payment_success
      end

      transitions from: [ :processing, :pending ], to: :succeeded
    end

    event :fail do
      # Guard: Can fail from created, pending, or processing
      guards :can_fail?

      before do
        self.failed_at = Time.current
        self.failure_reason = @failure_reason if @failure_reason
      end

      after do
        # Notify merchant of failure
        notify_merchant(:failure)
        # Log failure
        log_payment_failure
        # Increment retry count
        increment_retry_count
      end

      transitions from: [ :created, :pending, :processing ], to: :failed
    end

    event :refund do
      # Guard: Only succeeded payments can be refunded
      guards :can_refund?

      before do
        self.refunded_at = Time.current
      end

      after do
        # Update order status if needed
        order.refund! if order.may_refund?
        # Notify merchant
        notify_merchant(:refund)
        # Log refund
        log_payment_refund
      end

      transitions from: :succeeded, to: :refunded
    end

    event :retry do
      # Guard: Only failed payments can be retried
      guards :can_retry?

      before do
        self.retry_count += 1
        self.failed_at = nil
        self.failure_reason = nil
      end

      after do
        # Queue for reprocessing
        PaymentProcessorJob.perform_later(id)
      end

      transitions from: :failed, to: :pending
    end
  end

  # Guards (business rules)
  def can_mark_pending?
    created? && order.present?
  end

  def can_mark_processing?
    (created? || pending?) && !succeeded? && !failed?
  end

  def can_succeed?
    (processing? || pending?) && provider_reference.present?
  end

  def can_fail?
    (created? || pending? || processing?) && failure_reason.present?
  end

  def can_refund?
    succeeded? && !refunded?
  end

  def can_retry?
    failed? && retry_count < 3
  end

  # Callbacks
  after_aasm_event :log_state_change
  after_aasm_event :update_order_status, if: -> { aasm.to_state == :succeeded }

  # Instance methods
  def amount
    amount_cents / 100.0
  end

  def amount_formatted
    format("%.2f %s", amount, currency)
  end

  def successful?
    status == "succeeded"
  end

  def failed?
    status == "failed"
  end

  def refundable?
    succeeded? && !refunded?
  end

  def status_label
    status.humanize
  end

  # Method to set provider reference before transition
  def succeed_with_reference(reference)
    @provider_reference = reference
    succeed!
  end

  def fail_with_reason(reason)
    @failure_reason = reason
    fail!
  end

  # Class methods
  class << self
    def find_by_idempotency_key(key, merchant_id)
      joins(:order)
        .where(orders: { merchant_id: merchant_id })
        .find_by(idempotency_key: key)
    end

    def total_by_merchant(merchant_id, currency = nil)
      query = where(status: :succeeded).by_merchant(merchant_id)
      query = query.by_currency(currency) if currency
      query.sum(:amount_cents)
    end

    def success_rate(merchant_id)
      total = by_merchant(merchant_id).count
      return 0 if total.zero?

      successful_count = where(status: :succeeded).by_merchant(merchant_id).count
      (successful_count.to_f / total * 100).round(2)
    end

    def average_payment_amount(merchant_id, currency = nil)
      query = where(status: :succeeded).by_merchant(merchant_id)
      query = query.by_currency(currency) if currency
      query.average(:amount_cents)&.to_i || 0
    end
  end

  private

  def amount_matches_order_total
    return unless order.present? && amount_cents.present?
    return if order.amount_cents == amount_cents

    errors.add(:amount_cents, "must match order total (#{order.amount_cents})")
  end

  def validate_payment_method
    valid_methods = [ "card", "bank_transfer", "paypal", "stripe", "square", "cash" ]
    unless valid_methods.include?(payment_method)
      errors.add(:payment_method, "must be one of: #{valid_methods.join(', ')}")
    end
  end

  def validate_card_details
    if card_last_four.present? && !card_last_four.match?(/\A\d{4}\z/)
      errors.add(:card_last_four, "must be 4 digits")
    end

    if card_brand.present? && !%w[visa mastercard amex discover jcb diners].include?(card_brand)
      errors.add(:card_brand, "invalid card brand")
    end
  end

  def log_state_change
    Rails.logger.info "Payment #{id} state changed: #{aasm.from_state} -> #{aasm.to_state}"
  end

  def update_order_status
    order.mark_paid! if order.may_mark_paid?
  end

  def notify_merchant(event)
    # Implement webhook notification logic
    Rails.logger.info "Notifying merchant about payment event: #{event}"
  end

  def log_payment_success
    Rails.logger.info "Payment succeeded: #{id}, reference: #{provider_reference}"
  end

  def log_payment_failure
    Rails.logger.info "Payment failed: #{id}, reason: #{failure_reason}"
  end

  def log_payment_refund
    Rails.logger.info "Payment refunded: #{id}"
  end

  def increment_retry_count
    self.retry_count ||= 0
    self.retry_count += 1
    save!
  end
end
