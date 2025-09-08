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
end