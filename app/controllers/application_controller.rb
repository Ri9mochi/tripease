class ApplicationController < ActionController::Base
  before_action :basic_auth
  before_action :authenticate_user!, unless: :devise_controller?
  before_action :configure_permitted_parameters, if: :devise_controller?

  private

  def basic_auth
    authenticate_or_request_with_http_basic do |username, password|
      username == ENV["BASIC_AUTH_USER"] && password == ENV["BASIC_AUTH_PASSWORD"]
    end
  end

  def after_sign_in_path_for(resource)
    travel_plans_path # ログイン後に遷移するパス
  end

  def after_sign_out_path_for(resource)
    new_user_session_path # ログアウト後に遷移するパス
  end

  protected

  # DeviseのStrong Parameters設定
  def configure_permitted_parameters
    keys = [:first_name, :last_name, :nickname, :home_destination_id]
    devise_parameter_sanitizer.permit(:sign_up,        keys: keys)
    devise_parameter_sanitizer.permit(:account_update, keys: keys)
  end
end
