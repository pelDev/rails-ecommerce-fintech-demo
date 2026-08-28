class UpdatePaymentStatusConstraints < ActiveRecord::Migration[8.1]
  def change
    # Remove old constraints
    remove_check_constraint :payments, name: "payments_status_valid_check"
    remove_check_constraint :payments, name: "payments_failure_reason_check"
    remove_check_constraint :payments, name: "payments_provider_reference_check"

    # Add new constraints
    add_check_constraint :payments,
      "status IN (0, 1, 2, 3, 4, 5)",
      name: "payments_status_valid_check"

    add_check_constraint :payments,
      "(status = 4 AND failure_reason IS NOT NULL) OR (status != 4 AND failure_reason IS NULL)",
      name: "payments_failure_reason_check"

    add_check_constraint :payments,
      "(status = 3 AND provider_reference IS NOT NULL) OR (status != 3)",
      name: "payments_provider_reference_check"
  end
end
