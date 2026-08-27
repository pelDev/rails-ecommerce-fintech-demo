class OrderItem < ApplicationRecord
  # Constants
  CURRENCIES = %w[USD EUR GBP JPY CAD AUD CHF CNY HKD NZD SEK KRW SGD NOK MXN INR BRL ZAR TRY RUB].freeze

  belongs_to :order

  # Validations
  validates :order, presence: true
  validates :product_name, presence: true, length: { maximum: 255 }
  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price_cents, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :total_price_cents, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :currency, presence: true, inclusion: { in: CURRENCIES }

  # Custom validations
  validate :total_price_matches_quantity_price

  # Callbacks
  before_validation :calculate_total_price, on: [ :create, :update ]

  # Instance methods
  def unit_price
    unit_price_cents / 100.0
  end

  def total_price
    total_price_cents / 100.0
  end

  def total_price_formatted
    format("%.2f %s", total_price, currency)
  end

  private

  def calculate_total_price
    self.total_price_cents = quantity * unit_price_cents if quantity.present? && unit_price_cents.present?
  end

  def total_price_matches_quantity_price
    return unless quantity.present? && unit_price_cents.present? && total_price_cents.present?

    calculated_total = quantity * unit_price_cents
    unless total_price_cents == calculated_total
      errors.add(:total_price_cents, "must equal #{calculated_total} (quantity * unit_price)")
    end
  end
end
