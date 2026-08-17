Rails.application.routes.draw do
  resources :import_columns_definitions do
    collection do
      post :analyze_csv, to: "csv_analyses#create"
    end
  end

  resources :categories

  # Counterparties.  A TradingAccount is an Account, but not one of the household's, so it does not go
  # through AccountsController: the shared form and detail partial are about sort codes and opening
  # balances, none of which a counterparty has.
  resources :trading_accounts

  resources :accounts do
    resources :transactions, only: [ :index, :new, :create, :edit, :update, :destroy ]
    # Rules belong to an account, so nesting them is what keeps that from being a field you have to
    # remember to set.
    resources :import_matchers
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
