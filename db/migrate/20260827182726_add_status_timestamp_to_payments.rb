class AddStatusTimestampToPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :payments, :pending_at, :datetime
    add_column :payments, :processing_at, :datetime
    add_column :payments, :succeeded_at, :datetime
    add_column :payments, :failed_at, :datetime
    add_column :payments, :refunded_at, :datetime
    add_column :payments, :retry_count, :integer, default: 0, null: false

    # Add indexes for monitoring
    add_index :payments, :succeeded_at
    add_index :payments, :failed_at
    add_index :payments, :refunded_at
    add_index :payments, :retry_count
  end
end
