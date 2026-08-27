class AddStatusTimestampToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :paid_at, :datetime
    add_column :orders, :shipped_at, :datetime
    add_column :orders, :delivered_at, :datetime
    add_column :orders, :cancelled_at, :datetime
    add_column :orders, :refunded_at, :datetime
    add_column :orders, :expired_at, :datetime

    # Add indexes for analytics
    add_index :orders, :paid_at
    add_index :orders, :delivered_at
    add_index :orders, :cancelled_at
    add_index :orders, :refunded_at
  end
end
