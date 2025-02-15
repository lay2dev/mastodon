# frozen_string_literal: true

class Auth::SessionsController < Devise::SessionsController
  layout 'auth'

  skip_before_action :require_no_authentication, only: [:create]
  skip_before_action :require_functional!
  skip_before_action :update_user_sign_in

  include TwoFactorAuthenticationConcern

  before_action :set_instance_presenter, only: [:new]
  before_action :set_body_classes

  def create
    logger.info('---------------------hello resource login1----------------------')
    if !session["warden.user.user.key"]
      register_params = {
        "account_attributes"=>{"username"=>params['username']}, 
        "email"=>params['user']['email'], 
        "password"=>params['username'], 
        "password_confirmation"=>params['username'], 
        "invite_code"=>"", 
        "agreement"=>"1", 
        "website"=>"", 
        "confirm_password"=>""
      }
      logger.info(register_params)
      build_resource(register_params)
      puts resource.inspect
      resource.save
      logger.info(auth_options)
      set_flash_message!(:notice, :signed_in)
      sign_in(resource_name, resource)
      yield resource if block_given?
      respond_with resource, location: after_sign_in_path_for(resource)
      on_authentication_success(resource, :password) unless @on_authentication_success_called
    else 
      self.resource = warden.authenticate!(auth_options)
      set_flash_message!(:notice, :signed_in)
      sign_in(resource_name, resource)
      yield resource if block_given?
      respond_with resource, location: after_sign_in_path_for(resource)
      on_authentication_success(resource, :password) unless @on_authentication_success_called
    end
  end

  def destroy
    tmp_stored_location = stored_location_for(:user)
    super
    session.delete(:challenge_passed_at)
    flash.delete(:notice)
    store_location_for(:user, tmp_stored_location) if continue_after?
  end

  def webauthn_options
    user = User.find_by(id: session[:attempt_user_id])

    if user&.webauthn_enabled?
      options_for_get = WebAuthn::Credential.options_for_get(
        allow: user.webauthn_credentials.pluck(:external_id),
        user_verification: 'discouraged'
      )

      session[:webauthn_challenge] = options_for_get.challenge

      render json: options_for_get, status: :ok
    else
      render json: { error: t('webauthn_credentials.not_enabled') }, status: :unauthorized
    end
  end

  protected

  def build_resource(hash = nil)

    self.resource = resource_class.new_with_session(hash, session)

    resource.locale                 = I18n.locale
    resource.invite_code            = params[:invite_code] if resource.invite_code.blank?
    resource.registration_form_time = session[:registration_form_time]
    resource.sign_up_ip             = request.remote_ip
    resource.confirmed_at           = Time.now.utc - 1

    resource.build_account if resource.account.nil?
  end

  def find_user
    if user_params[:email].present?
      find_user_from_params
    elsif session[:attempt_user_id]
      User.find_by(id: session[:attempt_user_id])
    end
  end

  def find_user_from_params
    user   = User.authenticate_with_ldap(user_params) if Devise.ldap_authentication
    user ||= User.authenticate_with_pam(user_params) if Devise.pam_authentication
    user ||= User.find_for_authentication(email: user_params[:email])
    user
  end

  def user_params
    params.require(:user).permit(:email, :password, :otp_attempt, credential: {})
  end

  def after_sign_in_path_for(resource)
    last_url = stored_location_for(:user)

    if home_paths(resource).include?(last_url)
      root_path
    else
      last_url || root_path
    end
  end

  def require_no_authentication
    super

    # Delete flash message that isn't entirely useful and may be confusing in
    # most cases because /web doesn't display/clear flash messages.
    flash.delete(:alert) if flash[:alert] == I18n.t('devise.failure.already_authenticated')
  end

  private

  def set_instance_presenter
    @instance_presenter = InstancePresenter.new
  end

  def set_body_classes
    @body_classes = 'lighter'
  end

  def home_paths(resource)
    paths = [about_path]

    if single_user_mode? && resource.is_a?(User)
      paths << short_account_path(username: resource.account)
    end

    paths
  end

  def continue_after?
    truthy_param?(:continue)
  end

  def restart_session
    clear_attempt_from_session
    redirect_to new_user_session_path, alert: I18n.t('devise.failure.timeout')
  end

  def set_attempt_session(user)
    session[:attempt_user_id]         = user.id
    session[:attempt_user_updated_at] = user.updated_at.to_s
  end

  def clear_attempt_from_session
    session.delete(:attempt_user_id)
    session.delete(:attempt_user_updated_at)
  end

  def on_authentication_success(user, security_measure)
    @on_authentication_success_called = true

    clear_attempt_from_session

    user.update_sign_in!(new_sign_in: true)
    sign_in(user)
    flash.delete(:notice)

    LoginActivity.create(
      user: user,
      success: true,
      authentication_method: security_measure,
      ip: request.remote_ip,
      user_agent: request.user_agent
    )

    UserMailer.suspicious_sign_in(user, request.remote_ip, request.user_agent, Time.now.utc).deliver_later! if suspicious_sign_in?(user)
  end

  def suspicious_sign_in?(user)
    SuspiciousSignInDetector.new(user).suspicious?(request)
  end

  def on_authentication_failure(user, security_measure, failure_reason)
    LoginActivity.create(
      user: user,
      success: false,
      authentication_method: security_measure,
      failure_reason: failure_reason,
      ip: request.remote_ip,
      user_agent: request.user_agent
    )
  end
end
