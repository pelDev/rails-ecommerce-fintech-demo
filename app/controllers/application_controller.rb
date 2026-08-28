class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def load_merchant_data
    redirect_to new_user_registration_path, alert: "No merchant record found." unless current_user&.merchant
    @merchant = current_user.merchant
  end
end
