class CreateMerchants < ActiveRecord::Migration[8.1]
  def change
    create_table :merchants do |t|
      t.string :name, null: false
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    # Add unique index on name
    add_index :merchants, :name, unique: true

    # Status should be within enum range (0-2 for typical statuses)
    reversible do |dir|
      dir.up do
        execute <<-SQL
          ALTER TABLE merchants
          ADD CONSTRAINT merchants_status_check
          CHECK (status IN (0, 1, 2))
        SQL
      end

      dir.down do
        execute <<-SQL
          ALTER TABLE merchants
          DROP CONSTRAINT IF EXISTS merchants_status_check
        SQL
      end
    end
  end
end
