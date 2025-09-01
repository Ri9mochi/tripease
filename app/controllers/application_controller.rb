class ApplicationController < ActionController::Base
  before_action :authenticate_user!, if: :devise_controller?

  private

  def after_sign_in_path_for(resource)
    travel_plans_path # ログイン後に遷移するパス
  end

  def after_sign_out_path_for(resource)
    new_user_session_path # ログアウト後に遷移するパス
  end
end
