Rails.application.routes.draw do
  resources :import_columns_definitions do
    collection do
      post :analyze_csv, to: "csv_analyses#create"
    end
  end

  resources :categories

  # The frequencies the reader has set by hand for one category's regular payments.  Here rather than in
  # the forecasting group below, because it is edited on the category screen and belongs to the category
  # — but it is forecast configuration, and the comment on that group explains the shape.  An upsert over
  # the whole screen's worth at once, so there is no `new`, no `create` and nothing to show.
  patch "categories/:category_id/payment_schedules", to: "payment_schedules#update",
        as: :category_payment_schedules

  # Counterparties.  A Counterparty is an Account, but not one of the household's, so it does not go
  # through AccountsController: the shared form and detail partial are about sort codes and opening
  # balances, none of which a counterparty has.
  resources :counterparties

  # Merging is its own resource rather than extra actions on CounterpartiesController, following the same
  # habit as CsvAnalysesController: the operation is the noun.  `new` confirms what is about to move and is
  # reached by a GET form from the counterparties list, carrying the ticked ids in the query string —
  # displaying a confirmation changes nothing, so it should be safe to reload or bookmark.  `create` is the
  # POST that actually moves anything.
  resources :counterparty_merges, only: [ :new, :create ]

  # Forecasting.  There is no resource to create — the whole screen is recomputed from the transactions
  # every time it is asked for — so these are plain routes rather than `resource :forecast`, whose nested
  # member helpers would read worse than the four names spelled out.  The month travels as `?month=`.
  get  "forecast",                       to: "forecasts#show",          as: :forecast
  get  "forecast/uncategorised",         to: "forecasts#uncategorised", as: :forecast_uncategorised
  get  "forecast/categories/:id",        to: "forecasts#category",      as: :forecast_category
  # The one thing the forecast stores: a figure typed in by hand.  An upsert, so there is no `new`.
  post "forecast/categories/:id/manual", to: "manual_forecasts#update", as: :forecast_category_manual

  resources :accounts do
    # No `edit`: a transaction is edited in place in its own row, so there is no form screen to route to.
    resources :transactions, only: [ :index, :new, :create, :update, :destroy ]
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
