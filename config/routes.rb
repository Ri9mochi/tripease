Rails.application.routes.draw do
  devise_for :users

  devise_scope :user do
    root to: 'devise/sessions#new'
  end

  authenticated :user do
    root to: 'travel_plans#index', as: :authenticated_root
  end

  resources :travel_plans, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
    collection do
      post :generate_ai
      get :preview
    end
  end
  # ▼▼▼ 一時的 seed 実行ルート（必ずあとで削除！） ▼▼▼
  if Rails.env.production?
    get "/__seed_once" => "seeds#run"
  end
  # ▲▲▲
end
