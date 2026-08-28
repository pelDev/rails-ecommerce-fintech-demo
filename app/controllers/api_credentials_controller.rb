class ApiCredentialsController < ApplicationController
    # Require authentication for all api credentials actions
    before_action :authenticate_user!

    # Load merchant-specific data
    before_action :load_merchant_data

    def index
        # Key status for quick developer check
        @api_credentials = @merchant.api_credentials.order(created_at: :desc)
    end

    def create
        @credential = @merchant.api_credentials.build

        if @credential.save
            # Store the raw secret temporarily in flash so it displays ONCE after redirect
            flash[:raw_secret] = @credential.raw_secret
            flash[:new_key] = @credential.key
            redirect_to api_credentials_path, notice: "API Credential successfully generated."
        else
            @api_credentials = @merchant.api_credentials.order(created_at: :desc)
            render :index, status: :unprocessable_entity
        end
    end

    def destroy
        credential = @merchant.api_credentials.find(params[:id])
    
        if credential.revoke!
            redirect_to api_credentials_path, notice: "API key revoked successfully."
        else
            redirect_to api_credentials_path, alert: "Failed to revoke API key."
        end
    end
end