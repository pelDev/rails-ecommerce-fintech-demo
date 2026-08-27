class CreateOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.string :product_name, null: false
      t.integer :quantity, null: false, default: 1
      t.integer :unit_price_cents, null: false
      t.string :currency, null: false, default: 'USD'
      t.integer :total_price_cents, null: false

      t.timestamps
    end

    # Indexes
    add_index :order_items, :product_name

    # Check constraints
    add_check_constraint :order_items, 'quantity > 0', name: 'order_items_quantity_positive_check'
    add_check_constraint :order_items, 'unit_price_cents > 0', name: 'order_items_unit_price_positive_check'
    add_check_constraint :order_items, 'total_price_cents > 0', name: 'order_items_total_price_positive_check'

    # Check that total_price = quantity * unit_price
    add_check_constraint :order_items,
                         'total_price_cents = quantity * unit_price_cents',
                         name: 'order_items_total_price_calculation_check'

    # Currency validation
    add_check_constraint :order_items,
                         "currency IN ('USD', 'EUR', 'GBP', 'JPY', 'CAD', 'AUD', 'CHF', 'CNY', 'HKD', 'NZD', 'SEK', 'KRW', 'SGD', 'NOK', 'MXN', 'INR', 'BRL', 'ZAR', 'TRY', 'RUB')",
                         name: 'order_items_currency_valid_check'
  end
end
