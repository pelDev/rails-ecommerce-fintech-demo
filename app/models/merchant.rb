class Merchant < ApplicationRecord
  # Associations
  has_many :api_credentials, dependent: :destroy

  # Enum definition for status
  enum :status, {
    active: 0,
    inactive: 1,
    suspended: 2
  }

  # Validations
  validates :name, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: statuses.keys }

  # Scopes for common queries
  scope :active, -> { where(status: :active) }
  scope :active_or_inactive, -> { where(status: [ :active, :inactive ]) }

  # Instance methods
  def active?
    status == "active"
  end

  def inactive?
    status == "inactive"
  end

  def suspended?
    status == "suspended"
  end

  def status_label
    status.humanize
  end

  def can_be_reactivated?
    suspended? || inactive?
  end

  def can_be_suspended?
    active? || inactive?
  end

  def active_api_credentials
    api_credentials.active
  end

  def has_active_api_credentials?
    active_api_credentials.exists?
  end

  # Callbacks
  before_validation :normalize_name
  after_commit :log_creation, on: :create

  private

  def normalize_name
    self.name = name.strip.titleize if name.present?
  end

  def log_creation
    Rails.logger.info "Merchant created: #{name} (#{status})"
  end
end
