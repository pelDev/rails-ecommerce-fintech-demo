class Api::V1::BaseController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate_api_credential!
  before_action :ensure_merchant_active!

  attr_reader :current_credential, :current_merchant

  private

  def authenticate_api_credential!
    key, secret = extract_credentials

    unless key.present? && secret.present?
      render_unauthorized("Missing API key or secret")
      return
    end

    # Authenticate using your custom class method
    @current_credential = ApiCredential.authenticate(key, secret)

    if @current_credential.nil?
      render_unauthorized("Invalid or inactive API credentials")
      return
    end

    @current_merchant = @current_credential.merchant
  end

  def ensure_merchant_active!
    return if current_merchant&.active? # Assuming Merchant has an active? method

    render_forbidden("Merchant account is suspended or inactive")
  end

  # Supports standard custom headers
  def extract_credentials
    key = request.headers["X-Api-Key"]
    secret = request.headers["X-Api-Secret"]
    return [key, secret] if key.present? && secret.present?

    [nil, nil]
  end

  def render_unauthorized(message)
    headers["WWW-Authenticate"] = 'Bearer realm="API"'
    render json: { error: message }, status: :unauthorized
  end

  def render_forbidden(message)
    render json: { error: message }, status: :forbidden
  end
end
