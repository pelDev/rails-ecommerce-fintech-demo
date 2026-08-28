class ApiCredential < ApplicationRecord
  attr_reader :raw_secret

  # Associations
  belongs_to :merchant

  # Validations
  validates :key, presence: true,
    uniqueness: { case_sensitive: true },
    length: { minimum: 16, maximum: 64 },
    format: {
      with: /\A[a-zA-Z0-9\-_]+\z/,
      message: "only allows letters, numbers, hyphens, and underscores"
    }

  validates :secret_digest, presence: true
  validates :active, inclusion: { in: [ true, false ] }

  # Custom validations
  validate :revoked_at_implies_inactive, if: -> { revoked_at.present? }
  validate :inactive_cannot_be_revoked_later, if: -> { revoked_at.nil? && active == false }

  # Scopes
  scope :active, -> { where(active: true, revoked_at: nil) }
  scope :revoked, -> { where(revoked_at: nil).where.not(active: false) }
  scope :for_merchant, ->(merchant_id) { where(merchant_id: merchant_id) }
  scope :expiring_soon, -> { where(created_at: 83.days.ago..90.days.ago) }

  # Callbacks
  before_validation :generate_key_and_secret, on: :create
  after_commit :log_credential_creation, on: :create

  # Instance methods
  def active?
    active == true && revoked_at.nil? && !expired?
  end

  def revoked?
    revoked_at.present? || active == false
  end

  def revoke!
    transaction do
      update!(active: false, revoked_at: Time.current)
    end
  end

  def reactivate!
    transaction do
      update!(active: true, revoked_at: nil)
    end
  end

  def expires_at
    created_at + 90.days
  end

  def expired?
    Time.current > expires_at
  end

  # Class methods
  class << self
    def authenticate(key, secret)
      credential = find_by(key: key)
      return nil unless credential&.active?

      # Use secure comparison to prevent timing attacks
      password = ::BCrypt::Password.new(credential.secret_digest)
      return credential if password == secret

      nil
    rescue ::BCrypt::Errors::InvalidHash
      nil
    end

    def generate_api_key
      SecureRandom.urlsafe_base64(32)
    end

    def generate_secret
      SecureRandom.urlsafe_base64(48)
    end
  end

  def generate_key_and_secret
    return if key.present? && secret_digest.present?
    
    self.key ||= self.class.generate_api_key
    @raw_secret = self.class.generate_secret
    self.secret_digest = ::BCrypt::Password.create(@raw_secret, cost: 12).to_s
  end

  def revoked_at_implies_inactive
    errors.add(:active, "must be false when revoked_at is present") if active == true
  end

  def inactive_cannot_be_revoked_later
    errors.add(:revoked_at, "must be present when inactive") if active == false
  end

  def log_credential_creation
    Rails.logger.info "API Credential created for merchant #{merchant_id} with key: #{key}"
  end
end
