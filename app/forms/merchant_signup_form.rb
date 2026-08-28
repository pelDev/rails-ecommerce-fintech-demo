class MerchantSignupForm
  include ActiveModel::Model
  include ActiveModel::Validations

  # Merchant Attributes
  attr_accessor :merchant_name

  # User Attributes (Devise + Custom)
  attr_accessor :first_name, :last_name, :email, :password, :password_confirmation

  # Output Readers
  attr_reader :merchant, :user

  # Merchant Validations
  validates :merchant_name, presence: true

  # User Validations (matching your User model requirements)
  validates :first_name, presence: true, length: { maximum: 50 }
  validates :last_name, presence: true, length: { maximum: 50 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true, confirmation: true, length: { minimum: 6 }

  def save
    return false unless valid?

    ActiveRecord::Base.transaction do
      @merchant = Merchant.create!(
        name: merchant_name,
        status: :active
      )

      @user = merchant.users.create!(
        first_name: first_name,
        last_name: last_name,
        email: email,
        password: password,
        password_confirmation: password_confirmation,
        role: "user", # Default creator to user
        active: true
      )
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    promote_errors(e.record.errors)
    false
  end

  private

  def promote_errors(child_errors)
    child_errors.each do |error|
      attribute = error.attribute == :name ? :merchant_name : error.attribute
      errors.add(attribute, error.message)
    end
  end
end