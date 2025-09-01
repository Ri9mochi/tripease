Rails.application.routes.draw do
  devise_for :users
  authenticated :user do
    root to: 'travel_plans#index', as: :authenticated_root
  end

  # ログインしていないユーザーがアクセスするルート
  root to: 'devise/sessions#new'
  
  resources :travel_plans
end
