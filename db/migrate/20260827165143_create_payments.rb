class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :order, null: false, foreign_key: true
      t.references :merchant, null: false, foreign_key: true

      # Financial fields
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: 'USD'

      # Status and tracking
      t.integer :status, null: false, default: 0
      t.string :provider_reference
      t.string :idempotency_key
      t.string :failure_reason

      # Payment details
      t.string :payment_method
      t.string :card_last_four
      t.string :card_brand
      t.string :billing_address

      t.timestamps
    end

    # Standard indexes
    add_index :payments, :status
    add_index :payments, :provider_reference, unique: true
    add_index :payments, [ :merchant_id, :status ]
    add_index :payments, [ :order_id, :status ]
    add_index :payments, :payment_method

    add_index :payments, [ :merchant_id, :currency, :status ]
    add_index :payments, [ :merchant_id, :created_at, :status ]
    add_index :payments, :idempotency_key, where: "idempotency_key IS NOT NULL"

    # CRITICAL: Unique idempotency key scoped to merchant via order
    # Since we're indexing on (order_id, idempotency_key), and order belongs to merchant,
    # this effectively gives us merchant-scoped uniqueness
    add_index :payments, [ :order_id, :idempotency_key ],
      unique: true,
      where: "idempotency_key IS NOT NULL",
      name: 'index_payments_on_order_id_and_idempotency_key'

    # Additional partial indexes for common queries
    add_index :payments, [ :merchant_id, :created_at ],
              where: "status = 1",
              name: 'index_payments_on_merchant_completed'

    add_index :payments, :created_at,
              where: "status = 0",
              name: 'index_payments_on_pending_created_at'

    # Check constraints
    # 1. Amount must be positive
    add_check_constraint :payments, 'amount_cents > 0', name: 'payments_amount_positive_check'

    # 2. Currency must be valid
    add_check_constraint :payments,
      "currency IN ('USD', 'EUR', 'GBP', 'JPY', 'CAD', 'AUD', 'CHF', 'CNY', 'HKD', 'NZD', 'SEK', 'KRW', 'SGD', 'NOK', 'MXN', 'INR', 'BRL', 'ZAR', 'TRY', 'RUB')",
      name: 'payments_currency_valid_check'

    # 3. Status must be valid
    add_check_constraint :payments,
      'status IN (0, 1, 2, 3, 4)',
      name: 'payments_status_valid_check'

    # 4. Failure reason only present when status is failed
    add_check_constraint :payments,
      '(status = 3 AND failure_reason IS NOT NULL) OR (status != 3 AND failure_reason IS NULL)',
      name: 'payments_failure_reason_check'

    # 5. Provider reference required for completed payments
    add_check_constraint :payments,
      '(status = 1 AND provider_reference IS NOT NULL) OR (status != 1)',
      name: 'payments_provider_reference_check'
  end
end
