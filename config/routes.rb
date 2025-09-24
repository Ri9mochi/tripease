Rails.application.routes.draw do
  # Render のヘルスチェック用エンドポイント（必ず 200 を返す）
  get "/up", to: proc { [200, { "Content-Type" => "text/plain" }, ["OK"]] }

  devise_for :users

  # 未ログイン時の root はログイン画面へ
  devise_scope :user do
    root to: 'devise/sessions#new'
  end

  # ログイン済みユーザーの root
  authenticated :user do
    root to: 'travel_plans#index', as: :authenticated_root
  end

  resources :travel_plans, only: %i[index new create show edit update destroy] do
    collection do
      post :generate_ai
      get  :preview
    end
  end
end
