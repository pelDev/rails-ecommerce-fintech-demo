class AddMetadataToPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :payments, :metadata, :jsonb, default: {}
    add_column :payments, :request_ip, :string
    add_column :payments, :user_agent, :string

    add_index :payments, :metadata, using: :gin
  end
end
