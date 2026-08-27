class Order < ApplicationRecord
  # Constants
  CURRENCIES = %w[USD EUR GBP JPY CAD AUD CHF CNY HKD NZD SEK KRW SGD NOK MXN INR BRL ZAR TRY RUB].freeze
  MINIMUM_AMOUNT = 1 # in cents

  # Enums
  enum :status, {
    pending: 0,
    paid: 1,
    shipped: 2,
    delivered: 3,
    cancelled: 4,
    refunded: 5
  }, prefix: true, scopes: true

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
  validates :status, presence: true, inclusion: { in: statuses.keys }
  validates :external_reference, uniqueness: true, allow_nil: true, length: { maximum: 255 }

  # Custom validations
  validate :validate_status_transition, on: :update
  validate :validate_external_reference_format, if: -> { external_reference.present? }

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

  # Instance methods
  def successful_payments
    payments.successful
  end

  def failed_payments
    payments.failed
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
    order_items.pluck(:product_name).join(', ')
  end

  def pending?
    status == "pending"
  end

  def shipped?
    status == "shipped"
  end

  def total_amount
    amount_cents / 100.0
  end

  def total_amount_formatted
    format("%.2f %s", total_amount, currency)
  end

  def paid?
    status.in?([ "paid", "shipped", "delivered" ])
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

  def mark_as_paid!
    return false unless pending?
    update!(status: :paid)
  end

  def mark_as_shipped!
    return false unless paid?
    update!(status: :shipped)
  end

  def mark_as_delivered!
    return false unless shipped?
    update!(status: :delivered)
  end

  def cancel!
    return false unless cancellable?
    update!(status: :cancelled)
  end

  def refund!
    return false unless refundable?
    transaction do
      update!(status: :refunded)
      payments.each { |payment| payment.refund! }
    end
  end

  # Class Methods
  class << self
    def total_revenue(currency = "USD")
      completed.where(currency: currency).sum(:amount_cents)
    end

    def average_order_value(currency = "USD")
      completed.where(currency: currency).average(:amount_cents)&.to_i || 0
    end

    def monthly_revenue(month, year, currency = "USD")
      start_date = Date.new(year, month, 1)
      end_date = start_date.end_of_month
      completed
        .by_currency(currency)
        .by_date_range(start_date, end_date)
        .sum(:amount_cents)
    end

    def revenue_by_merchant(merchant_id, currency = "USD")
      completed
        .by_merchant(merchant_id)
        .by_currency(currency)
        .sum(:amount_cents)
    end
  end

  private

  def validate_status_transition
    return if status_was.nil? || status.nil?

    # Define valid transitions
    valid_transitions = {
      "pending" => [ "paid", "cancelled"],
      "paid" => [ "shipped", "cancelled", "refunded" ],
      "shipped" => [ "delivered" ],
      "delivered" => [],
      "cancelled" => [],
      "refunded" => []
    }

    if valid_transitions[status_was] && !valid_transitions[status_was].include?(status)
      errors.add(:status, "cannot transition from #{status_was} to #{status}")
    end
  end

  def validate_external_reference_format
    unless external_reference.match?(/\A[a-zA-Z0-9\-_]+\z/)
      errors.add(:external_reference, "only allows letters, numbers, hyphens, and underscores")
    end
  end

  def normalize_currency
    self.currency = currency.to_s.upcase if currency.present?
  end

  def normalize_external_reference
    self.external_reference = external_reference.strip.presence if external_reference.present?
  end

  def log_order_creation
    Rails.logger.info "Order created: ID=#{id}, Merchant=#{merchant_id}, Amount=#{amount_cents} #{currency}"
  end

  def log_order_status_change
    Rails.logger.info "Order #{id} status changed from #{status_was} to #{status}"
  end
end
