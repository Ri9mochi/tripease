# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  # Basic認証は環境変数があるときのみ有効化し、/up とアセット等は除外
  before_action :basic_auth, if: :basic_auth_enabled?

  # Devise
  before_action :authenticate_user!, unless: :devise_controller?
  before_action :configure_permitted_parameters, if: :devise_controller?

  private

  # Basic認証を有効化するか
  def basic_auth_enabled?
    ENV["BASIC_AUTH_USER"].present? && ENV["BASIC_AUTH_PASSWORD"].present?
  end

  # Basic認証本体（/up やアセットは素通し）
  def basic_auth
    path = request.path.to_s

    # ヘルスチェックやアセット、ActiveStorage、ファビコン等は除外
    return if path.start_with?("/up", "/assets", "/packs", "/vite") ||
              path == "/favicon.ico" ||
              path == "/robots.txt" ||
              path =~ %r{\A/rails/active_storage/}

    authenticate_or_request_with_http_basic("Restricted") do |username, password|
      valid_basic_auth?(username, password)
    end
  end

  # timing attack 耐性のある比較（長さ不一致時の例外は false にする）
  def valid_basic_auth?(username, password)
    u_env = ENV["BASIC_AUTH_USER"].to_s
    p_env = ENV["BASIC_AUTH_PASSWORD"].to_s
    secure_equal(username, u_env) && secure_equal(password, p_env)
  end

  def secure_equal(a, b)
    ActiveSupport::SecurityUtils.secure_compare(a.to_s, b.to_s)
  rescue
    false
  end

  def after_sign_in_path_for(_resource)
    travel_plans_path # ログイン後に遷移するパス
  end

  def after_sign_out_path_for(_resource)
    new_user_session_path # ログアウト後に遷移するパス
  end

  protected

  # DeviseのStrong Parameters設定
  def configure_permitted_parameters
    keys = %i[first_name last_name nickname home_destination_id]
    devise_parameter_sanitizer.permit(:sign_up,        keys: keys)
    devise_parameter_sanitizer.permit(:account_update, keys: keys)
  end
end
