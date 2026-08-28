class Order < ApplicationRecord
  include AASM

  # Constants
  CURRENCIES = %w[USD EUR GBP JPY CAD AUD CHF CNY HKD NZD SEK KRW SGD NOK MXN INR BRL ZAR TRY RUB].freeze
  MINIMUM_AMOUNT = 1 # in cents

  # Define the enum mapping to match db values
  enum :status, {
    pending: 0,
    paid: 1,
    shipped: 2,
    delivered: 3,
    cancelled: 4,
    refunded: 5,
    expired: 6
  }

  # Associations
  belongs_to :merchant
  has_many :order_items, dependent: :destroy
  accepts_nested_attributes_for :order_items, allow_destroy: true
  has_many :payments, dependent: :destroy
  has_many :refunds, through: :payments

  # Validations
  validates :merchant, presence: true
  validates :amount_cents, presence: true,
  numericality: {
    only_integer: true,
    greater_than: 0,
    less_than_or_equal_to: 999_999_999 # $9,999,999.99 max
  }
  validates :currency, presence: true, inclusion: { in: CURRENCIES }
  validates :status, presence: true
  validates :external_reference, uniqueness: true, allow_nil: true, length: { maximum: 255 }

  # Custom validations
  validate :validate_external_reference_format, if: -> { external_reference.present? }

  # AASM State Machine
  aasm column: :status do
    # States
    state :pending, initial: true
    state :paid
    state :shipped
    state :delivered
    state :cancelled
    state :refunded
    state :expired

    after_all_transitions :log_state_change
    after_all_transitions :update_merchant_metrics, if: -> { aasm.to_state == :paid }

    # Events
    event :mark_paid do
      before { self.paid_at = Time.current }
      transitions from: :pending, to: :paid, guard: :can_mark_paid?
    end

    event :mark_shipped do
      before { self.shipped_at = Time.current }
      transitions from: :paid, to: :shipped, guard: :can_mark_shipped?
    end

    event :mark_delivered do
      before { self.delivered_at = Time.current }
      transitions from: :shipped, to: :delivered, guard: :can_mark_delivered?
    end

    event :cancel do
      before { self.cancelled_at = Time.current }
      after { refund_payments if paid? }
      transitions from: [:pending, :paid], to: :cancelled, guard: :can_cancel?
    end

    event :refund do
      before { self.refunded_at = Time.current }
      after { refund_payments }
      transitions from: :paid, to: :refunded, guard: :can_refund?
    end

    event :expire do
      before { self.expired_at = Time.current }
      transitions from: :pending, to: :expired, guard: :can_expire?
    end
  end

  # Scopes
  scope :by_merchant, ->(merchant_id) { where(merchant_id: merchant_id) }
  scope :by_status, ->(status) { where(status: status) }
  scope :by_currency, ->(currency) { where(currency: currency) }
  scope :by_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }
  scope :by_amount_range, ->(min, max) { where(amount_cents: min..max) }
  scope :with_external_reference, -> { where.not(external_reference: nil) }
  scope :without_external_reference, -> { where(external_reference: nil) }

  # Payment status scopes
  scope :awaiting_payment, -> { pending }
  scope :completed, -> { where(status: [ :paid, :shipped, :delivered ]) }
  scope :in_progress, -> { where(status: [ :pending, :paid, :shipped ]) }
  scope :not_cancelled, -> { where.not(status: [ :cancelled, :refunded ]) }

  # Callbacks
  before_validation :normalize_currency
  before_validation :normalize_external_reference
  after_create :log_order_creation
  after_update :log_order_status_change, if: -> { saved_change_to_status? }

  # Guards (business rules)
  def can_mark_paid?
    pending? && !expired? && payments.successful.exists?
  end

  def can_mark_shipped?
    paid? && !cancelled? && !refunded?
  end

  def can_mark_delivered?
    shipped? && !cancelled? && !refunded?
  end

  def can_cancel?
    (pending? || paid?) && !shipped? && !delivered?
  end

  def can_refund?
    paid? && !cancelled? && !refunded?
  end

  def can_expire?
    pending? && created_at < 24.hours.ago
  end

  # Instance methods
  def total_amount
    amount_cents / 100.0
  end

  def total_amount_formatted
    format("%.2f %s", total_amount, currency)
  end

  def paid?
    status == "paid"
  end

  def completed?
    status.in?([ "delivered", "paid", "shipped" ])
  end

  def cancellable?
    pending? || paid?
  end

  def refundable?
    paid? && !refunded?
  end

  def status_label
    status.humanize
  end

  def subtotal
    order_items.sum(:total_price_cents)
  end

  def recalculate_total!
    new_total = order_items.sum(:total_price_cents)
    update_column(:amount_cents, new_total)
    new_total
  end

  def item_count
    order_items.sum(:quantity)
  end

  def product_names
    order_items.pluck(:product_name).join(", ")
  end

  def total_paid
    payments.successful.sum(:amount_cents)
  end

  def fully_paid?
    total_paid >= amount_cents
  end

  def payment_status
    return "unpaid" if payments.empty?
    return "partially_paid" if total_paid < amount_cents && total_paid > 0
    return "paid" if fully_paid?
    "overpaid" if total_paid > amount_cents
  end

  def latest_payment
    payments.order(created_at: :desc).first
  end

  def successful_payments
    payments.successful
  end

  def failed_payments
    payments.failed
  end

  # Class Methods
  class << self
    def total_revenue(currency = "USD")
      where(status: [ :paid, :shipped, :delivered ])
        .where(currency: currency)
        .sum(:amount_cents)
    end

    def average_order_value(currency = "USD")
      where(status: [ :paid, :shipped, :delivered ])
        .where(currency: currency)
        .average(:amount_cents)&.to_i || 0
    end

    def monthly_revenue(month, year, currency = "USD")
      start_date = Date.new(year, month, 1)
      end_date = start_date.end_of_month
      where(status: [ :paid, :shipped, :delivered ])
        .where(currency: currency)
        .where(created_at: start_date..end_date)
        .sum(:amount_cents)
    end

    def revenue_by_merchant(merchant_id, currency = "USD")
      where(status: [ :paid, :shipped, :delivered ])
        .by_merchant(merchant_id)
        .where(currency: currency)
        .sum(:amount_cents)
    end

    def expire_pending_orders!
      where(status: :pending)
        .where("created_at < ?", 24.hours.ago)
        .find_each(&:expire!)
    end
  end

  private

  def validate_external_reference_format
    unless external_reference.match?(/\A[a-zA-Z0-9\-_]+\z/)
      errors.add(:external_reference, "only allows letters, numbers, hyphens, and underscores")
    end
  end

  def log_state_change
    Rails.logger.info "Order #{id} state changed: #{aasm.from_state} -> #{aasm.to_state}"
  end

  def update_merchant_metrics
    # Update merchant metrics when order is paid
    merchant.update_last_order_metrics! if merchant.respond_to?(:update_last_order_metrics!)
  end

  def refund_payments
    payments.successful.find_each(&:refund!)
  end

  def log_order_creation
    Rails.logger.info "Order created: ID=#{id}, Merchant=#{merchant_id}, Amount=#{amount_cents} #{currency}"
  end

  def log_order_status_change
    Rails.logger.info "Order #{id} status changed from #{status_was} to #{status}"
  end

  def normalize_currency
    self.currency = currency.to_s.upcase.strip if currency.present?
  end

  def normalize_external_reference
    return if external_reference.nil?
    self.external_reference = external_reference.strip.presence
  end

  private

  def validate_order_status_transition
    return unless status_changed? && !new_record?

    current = aasm.current_state
    target = status.to_sym

    # Check if the target state is reachable through any event
    reachable = AASM::Core::TransitionCollection.new(
      aasm, events: aasm.events(current)
    ).transitions.any? { |t| t.to == target }

    return if reachable || current == target

    errors.add(:status, "cannot transition from #{current} to #{target}")
  end
end
