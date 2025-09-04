Rails.application.routes.draw do
  devise_for :users

  authenticated :user do
    root to: 'travel_plans#index', as: :authenticated_root
  end

  devise_scope :user do
    root to: 'devise/sessions#new'
  end

  resources :travel_plans, only: [:index, :new, :create, :show] do
    collection do
      post :generate_ai  # AjaxでAIプランを生成
    end
    member do
      get :preview # 新しいルートを追加
    end
    
  end
end