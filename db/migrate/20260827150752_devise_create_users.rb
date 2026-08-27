# frozen_string_literal: true

class DeviseCreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      ## Merchant association
      t.references :merchant, null: false, foreign_key: true, index: true

      ## Database authenticatable
      t.string :email,              null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      ## Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Rememberable
      t.datetime :remember_created_at

      ## Trackable
      t.integer  :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip

      ## Confirmable
      t.string   :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string   :unconfirmed_email # Only if using reconfirmable

      ## Lockable
      t.integer  :failed_attempts, default: 0, null: false # Only if lock strategy is :failed_attempts
      t.string   :unlock_token # Only if unlock strategy is :email or :both
      t.datetime :locked_at

      ## Custom fields
      t.string :first_name
      t.string :last_name
      t.string :role, default: "user", null: false
      t.boolean :active, default: true, null: false
      t.datetime :last_activity_at


      t.timestamps null: false
    end

    add_index :users, :email,                unique: true
    add_index :users, :reset_password_token, unique: true
    add_index :users, :confirmation_token,   unique: true
    add_index :users, :unlock_token,         unique: true

    # Additional indexes for performance
    add_index :users, :role
    add_index :users, :active
    add_index :users, [ :merchant_id, :active ]
    add_index :users, [ :merchant_id, :role ]

    # Check constraint for role values
    reversible do |dir|
      dir.up do
        execute <<-SQL
          ALTER TABLE users
          ADD CONSTRAINT users_role_check
          CHECK (role IN ('user', 'admin', 'super_admin'))
        SQL
      end

      dir.down do
        execute <<-SQL
          ALTER TABLE users
          DROP CONSTRAINT IF EXISTS users_role_check
        SQL
      end
    end
  end
end
