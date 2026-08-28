class OrderCreationForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Attributes for the order itself
  attribute :currency, :string, default: 'USD'
  attribute :external_reference, :string

  # We'll accept a merchant instance or a merchant_id
  attr_accessor :merchant
  attr_accessor :order_items_attributes

  validates :merchant, presence: true
  validates :currency, presence: true, inclusion: { in: %w[USD EUR GBP JPY CAD AUD CHF CNY HKD NZD SEK KRW SGD NOK MXN INR BRL ZAR TRY RUB] }
  validate :validate_uniqueness_of_external_reference
  validate :validate_order_items

  def order_items_attributes=(value)
    @order_items_attributes = value.is_a?(Array) ? value : (value&.values || [])
  end

  def order_items_attributes
    @order_items_attributes ||= []
  end

  def save
    return false unless valid?

    ActiveRecord::Base.transaction do
      order = merchant.orders.build(
        currency: currency,
        external_reference: external_reference.presence,
        amount_cents: total_amount_cents,
        status: :pending # initial status
      )

      order_items_attributes.each do |item_attrs|
        order.order_items.build(
          product_name: item_attrs[:product_name],
          quantity: item_attrs[:quantity],
          unit_price_cents: item_attrs[:unit_price_cents],
          currency: currency, # same as order
          total_price_cents: item_attrs[:quantity] * item_attrs[:unit_price_cents]
        )
      end

      order.save!
      @order = order
      true
    end
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.message)
    false
  end

  def order
    @order
  end

  private

  def total_amount_cents
    order_items_attributes.sum { |item| item[:quantity] * item[:unit_price_cents] }
  end

  def validate_uniqueness_of_external_reference
    return if external_reference.blank?
    return unless merchant

    if merchant.orders.where(external_reference: external_reference).exists?
      errors.add(:external_reference, 'already taken for this merchant')
    end
  end

  def validate_order_items
    if order_items_attributes.empty?
      errors.add(:order_items, 'must have at least one item')
      return
    end

    order_items_attributes.each_with_index do |item, idx|
      if item[:product_name].blank?
        errors.add(:"order_items_attributes[#{idx}].product_name", "can't be blank")
      end
      if item[:quantity].to_i <= 0
        errors.add(:"order_items_attributes[#{idx}].quantity", 'must be greater than 0')
      end
      if item[:unit_price_cents].to_i <= 0
        errors.add(:"order_items_attributes[#{idx}].unit_price_cents", 'must be greater than 0')
      end
    end
  end
end