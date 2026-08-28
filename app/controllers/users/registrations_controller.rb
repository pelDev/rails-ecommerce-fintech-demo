class Users::RegistrationsController < Devise::RegistrationsController
  def new
    @signup_form = MerchantSignupForm.new
    render :new
  end

  def create
    @signup_form = MerchantSignupForm.new(signup_params)

    if @signup_form.save
      @user = @signup_form.user
      yield @user if block_given?

      if @user.persisted?
        if @user.active_for_authentication?
          set_flash_message! :notice, :signed_up
          sign_up(resource_name, @user)
          respond_with @user, location: after_sign_up_path_for(@user)
        else
          set_flash_message! :notice, :"signed_up_but_#{@user.inactive_message}"
          expire_data_after_sign_in!
          respond_with @user, location: after_inactive_sign_up_path_for(@user)
        end
      end
    else
      clean_up_passwords(@signup_form)
      render :new, status: :unprocessable_entity
    end
  end

  private

  def signup_params
    params.require(:merchant_signup_form).permit(
      :merchant_name,
      :first_name,
      :last_name,
      :email,
      :password,
      :password_confirmation
    )
  end

  def clean_up_passwords(object)
    object.password = nil
    object.password_confirmation = nil
  end
end