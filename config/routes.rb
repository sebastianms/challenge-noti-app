Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up"      => "rails/health#show", as: :rails_health_check
  get "metrics" => "metrics#show"

  namespace :webhooks do
    post "sendgrid", to: "sendgrid_events#create"
  end

  devise_for :admin_users,
             path: "admin",
             path_names: { sign_in: "login", sign_out: "logout" },
             controllers: { sessions: "admin/sessions" },
             skip: [ :registrations, :confirmations, :passwords ]

  namespace :admin do
    get  "dashboard", to: "dashboard#index", as: :dashboard
    resources :rules, only: [ :index, :new, :create, :edit, :update, :destroy ] do
      member { get :history }
    end
    resource  :mock_data, only: [ :create ]
    resources :audits,    only: [ :index, :show ], param: :correlation_id
    resources :blacklist,  only: [ :index, :create, :destroy ]
    resources :templates,  only: [ :index, :new, :create, :edit, :update, :destroy ] do
      member { post :preview }
    end
    resources :dlq, only: [ :index ] do
      member     { post :retry; post :discard }
      collection { post :bulk_retry }
    end
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
