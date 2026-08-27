class CreateApiCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :api_credentials do |t|
      t.references :merchant, null: false, foreign_key: true
      t.string :key, null: false
      t.string :secret_digest, null: false
      t.boolean :active, null: false, default: true
      t.datetime :revoked_at

      t.timestamps
    end

    # Unique index on key
    add_index :api_credentials, :key, unique: true

    # Composite index for common queries
    add_index :api_credentials, [ :merchant_id, :active ]
    add_index :api_credentials, [ :merchant_id, :revoked_at ]
  end
end
