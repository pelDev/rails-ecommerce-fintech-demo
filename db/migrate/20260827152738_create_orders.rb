class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :merchant, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: 'USD'
      t.integer :status, null: false, default: 0
      t.string :external_reference

      t.timestamps
    end

    # Basic indexes
    add_index :orders, :status
    add_index :orders, :external_reference, unique: true
    add_index :orders, [:merchant_id, :status]
    add_index :orders, [:merchant_id, :created_at]
    add_index :orders, [:merchant_id, :external_reference]

    # Partial indexes for common queries
    add_index :orders, :created_at, where: "status = 0", name: 'index_orders_on_pending_created_at'
    add_index :orders, [:merchant_id, :created_at], where: "status = 1", name: 'index_orders_on_merchant_completed'

    # 1. Amount must be positive
    add_check_constraint :orders, 'amount_cents > 0', name: 'orders_amount_positive_check'

    # 2. External reference must be unique and non-empty when present
    add_check_constraint :orders, 'external_reference IS NULL OR LENGTH(TRIM(external_reference)) > 0', name: 'orders_external_reference_not_empty_check'

    # 3. Currency must be a valid ISO 4217 code
    add_check_constraint :orders, "currency IN ('USD', 'EUR', 'GBP', 'JPY', 'CAD', 'AUD', 'CHF', 'CNY', 'HKD', 'NZD', 'SEK', 'KRW', 'SGD', 'NOK', 'MXN', 'INR', 'BRL', 'ZAR', 'TRY', 'RUB')", name: 'orders_currency_valid_check'

    # 4. Status must be within valid range
    add_check_constraint :orders, 'status IN (0, 1, 2, 3, 4, 5)', name: 'orders_status_valid_check'
  end
end
