Rails.application.routes.draw do
  resources :import_columns_definitions do
    collection do
      post :analyze_csv # Add this line
    end
  end

  resources :import_matchers
  resources :categories
  resources :transactions

  resources :accounts do
    resources :transactions, only: [:index, :new, :create] do
      collection do
        get :import
        post :import_process
      end
    end
  end

  resources :bank_accounts, controller: :accounts
  resources :credit_card_accounts, controller: :accounts

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "accounts#index"
end
