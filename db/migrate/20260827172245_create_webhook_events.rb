class CreateWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_events do |t|
      t.string :provider_event_id, null: false
      t.jsonb :payload, null: false, default: '{}'
      t.string :signature, null: false
      t.datetime :processed_at

      # Additional metadata for debugging
      t.string :event_type
      t.string :provider
      t.string :source_ip
      t.string :user_agent
      t.integer :processing_status, default: 0, null: false
      t.text :processing_error
      t.datetime :failed_at
      t.integer :retry_count, default: 0, null: false

      t.timestamps
    end

    add_index :webhook_events, :provider_event_id, unique: true

    # Additional indexes for querying and monitoring
    add_index :webhook_events, :processed_at
    add_index :webhook_events, :created_at
    add_index :webhook_events, [ :event_type, :created_at ]
    add_index :webhook_events, :processing_status
    add_index :webhook_events, [ :provider, :event_type ]
    add_index :webhook_events, :failed_at, where: "failed_at IS NOT NULL"

    # Check constraints for data integrity
    add_check_constraint :webhook_events, 'LENGTH(provider_event_id) > 0', name: 'webhook_events_provider_event_id_not_empty_check'

    add_check_constraint :webhook_events, 'processing_status IN (0, 1, 2, 3)', name: 'webhook_events_status_valid_check'

    add_check_constraint :webhook_events, '(processing_status = 3 AND processing_error IS NOT NULL) OR (processing_status != 3)', name: 'webhook_events_error_check'
  end
end
