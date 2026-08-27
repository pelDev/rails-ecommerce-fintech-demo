class Merchant < ApplicationRecord
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

  # Callbacks
  before_validation :normalize_name

  private

  def normalize_name
    self.name = name.strip.titleize if name.present?
  end
end
