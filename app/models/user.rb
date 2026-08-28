class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :timeoutable

  # Associations
  belongs_to :merchant

  # Validations
  validates :first_name, presence: true, length: { maximum: 50 }
  validates :last_name, presence: true, length: { maximum: 50 }
  validates :role, presence: true, inclusion: { in: %w[user admin super_admin] }
  validates :active, inclusion: { in: [ true, false ] }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :admins, -> { where(role: [ "admin", "super_admin" ]) }
  scope :by_merchant, ->(merchant_id) { where(merchant_id: merchant_id) }
  scope :recently_active, -> { where("last_activity_at > ?", 30.minutes.ago) }

  # Callbacks
  before_validation :normalize_names
  after_create :log_user_creation
  after_update :log_user_update, if: -> { saved_change_to_active? }

  # Instance methods
  def full_name
    [first_name, last_name].compact.join(' ').presence || email
  end

  def admin?
    role.in?(['admin', 'super_admin'])
  end

  def super_admin?
    role == 'super_admin'
  end

  def active_for_authentication?
    super && active?
  end

  def inactive_message
    active? ? super : :account_inactive
  end

  def update_last_activity!
    update_column(:last_activity_at, Time.current)
  end

  def can_manage_merchant?(merchant_id)
    return true if super_admin?
    return false unless self.merchant_id == merchant_id
    admin? || role == 'user'
  end

  # Class methods
  class << self
    def with_active_sessions
      where("last_activity_at > ?", 30.minutes.ago)
    end

    def search(query)
      where("first_name ILIKE ? OR last_name ILIKE ? OR email ILIKE ?", 
            "%#{query}%", "%#{query}%", "%#{query}%")
    end
  end

  private

  def normalize_names
    self.first_name = first_name.strip.titleize if first_name.present?
    self.last_name = last_name.strip.titleize if last_name.present?
  end

  def log_user_creation
    Rails.logger.info "User created: #{email} (#{role}) for merchant #{merchant_id}"
  end

  def log_user_update
    status = active? ? 'activated' : 'deactivated'
    Rails.logger.info "User #{email} #{status} by #{current_user&.email || 'system'}"
  end
end
