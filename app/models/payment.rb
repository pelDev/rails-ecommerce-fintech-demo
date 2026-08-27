class Payment < ApplicationRecord
  # Constants
  CURRENCIES = %w[USD EUR GBP JPY CAD AUD CHF CNY HKD NZD SEK KRW SGD NOK MXN INR BRL ZAR TRY RUB].freeze
  MINIMUM_AMOUNT = 1 # in cents
  MAXIMUM_AMOUNT = 999_999_999 # $9,999,999.99 max

  # Enums
  enum :status, {
    pending: 0,
    completed: 1,
    processing: 2,
    failed: 3,
    refunded: 4
  }, prefix: true, scopes: true

  # Associations
  belongs_to :order
  belongs_to :merchant # Denormalized for performance

  # Validations
  validates :order, presence: true
  validates :merchant, presence: true
  validates :amount_cents, presence: true,
  numericality: {
    only_integer: true,
    greater_than: 0,
    less_than_or_equal_to: MAXIMUM_AMOUNT
  }
  validates :currency, presence: true, inclusion: { in: CURRENCIES }
  validates :status, presence: true, inclusion: { in: statuses.keys }
  validates :idempotency_key, uniqueness: {
    scope: :order_id,
    message: "already used for this order"
  },
  allow_nil: true,
  length: { maximum: 255 }
  validates :provider_reference, uniqueness: true,
    allow_nil: true,
    length: { maximum: 255 }
  validates :failure_reason, length: { maximum: 500 }, allow_nil: true

  # Custom validations
  validate :amount_matches_order_total, if: -> { order.present? }
  validate :validate_status_transition, on: :update
  validate :validate_failure_reason_presence, if: -> { status == "failed" }
  validate :validate_provider_reference_presence, if: -> { status == "completed" }
  validate :validate_payment_method, if: -> { payment_method.present? }
  validate :validate_card_details, if: -> { payment_method == "card" }

  # Scopes
  scope :by_merchant, ->(merchant_id) { where(merchant_id: merchant_id) }
  scope :by_order, ->(order_id) { where(order_id: order_id) }
  scope :by_status, ->(status) { where(status: status) }
  scope :by_currency, ->(currency) { where(currency: currency) }
  scope :by_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }
  scope :successful, -> { where(status: [ :completed, :processing ]) }
  scope :failed_payments, -> { where(status: :failed) }
  scope :by_payment_method, ->(method) { where(payment_method: method) }
  scope :with_idempotency_key, -> { where.not(idempotency_key: nil) }
  scope :with_provider_reference, -> { where.not(provider_reference: nil) }

  # Callbacks
  before_validation :normalize_currency
  before_validation :normalize_fields
  before_validation :set_merchant_from_order, on: :create
  before_create :set_initial_status
  after_create :log_payment_creation
  after_update :log_payment_status_change, if: -> { saved_change_to_status? }

  # Instance methods
  def amount
    amount_cents / 100.0
  end

  def amount_formatted
    format("%.2f %s", amount, currency)
  end

  def successful?
    status.in?([ "completed", "processing" ])
  end

  def failed?
    status == "failed"
  end

  def pending?
    status == "pending"
  end

  def refundable?
    completed? && !refunded?
  end

  def status_label
    status.humanize
  end

  # Status transition methods
  def mark_as_processing!
    return false unless pending?
    update!(status: :processing)
  end

  def mark_as_completed!(provider_ref)
    return false unless processing? || pending?
    transaction do
      update!(status: :completed, provider_reference: provider_ref)
      order.mark_as_paid! if order.pending?
    end
  end

  def mark_as_failed!(reason)
    return false if completed? || refunded?
    update!(status: :failed, failure_reason: reason)
  end

  def refund!
    return false unless refundable?
    transaction do
      update!(status: :refunded)
      # Create a refund record or mark order as refunded
    end
  end

  # Class methods
  class << self
    def find_by_idempotency_key(key, merchant_id)
      joins(:order)
        .where(orders: { merchant_id: merchant_id })
        .find_by(idempotency_key: key)
    end

    def total_by_merchant(merchant_id, currency = nil)
      query = successful.by_merchant(merchant_id)
      query = query.by_currency(currency) if currency
      query.sum(:amount_cents)
    end

    def success_rate(merchant_id)
      total = by_merchant(merchant_id).count
      return 0 if total.zero?

      successful_count = successful.by_merchant(merchant_id).count
      (successful_count.to_f / total * 100).round(2)
    end

    def average_payment_amount(merchant_id, currency = nil)
      query = successful.by_merchant(merchant_id)
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

  def validate_status_transition
    return if status_was.nil? || status.nil?

    # Define valid transitions
    valid_transitions = {
      "pending" => [ "processing", "failed" ],
      "processing" => [ "completed", "failed" ],
      "completed" => [ "refunded" ],
      "failed" => [ "pending", "processing" ],
      "refunded" => []
    }

    if valid_transitions[status_was] && !valid_transitions[status_was].include?(status)
      errors.add(:status, "cannot transition from #{status_was} to #{status}")
    end
  end

  def validate_failure_reason_presence
    if failure_reason.blank?
      errors.add(:failure_reason, "must be present when status is failed")
    end
  end

  def validate_provider_reference_presence
    if provider_reference.blank?
      errors.add(:provider_reference, "must be present when status is completed")
    end
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

  def normalize_currency
    self.currency = currency.to_s.upcase if currency.present?
  end

  def normalize_fields
    self.idempotency_key = idempotency_key.strip.presence if idempotency_key.present?
    self.provider_reference = provider_reference.strip.presence if provider_reference.present?
    self.failure_reason = failure_reason.strip.presence if failure_reason.present?
    self.card_last_four = card_last_four.strip if card_last_four.present?
    self.card_brand = card_brand.strip.downcase if card_brand.present?
    self.payment_method = payment_method.strip.downcase if payment_method.present?
  end

  def set_merchant_from_order
    self.merchant = order.merchant if order.present? && merchant.nil?
  end

  def set_initial_status
    self.status ||= :pending
  end

  def log_payment_creation
    Rails.logger.info "Payment created: ID=#{id}, Order=#{order_id}, Amount=#{amount_cents} #{currency}"
  end

  def log_payment_status_change
    Rails.logger.info "Payment #{id} status changed from #{status_was} to #{status}"
  end
end
