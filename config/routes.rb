Rails.application.routes.draw do
  devise_for :users, controllers: {
    registrations: "users/registrations"
  }

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  get "dashboard", to: "dashboard#index", as: :dashboard
  resources :api_credentials, only: [:index, :create, :destroy]
  
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      resources :orders, only: [:index, :create] do
        collection do
          get :ping
        end
      end

      # Expose endpoint to generate/manage API credentials
      resources :api_credentials, only: [:create, :index, :destroy]
    end
  end

  # Defines the root path route ("/")
  root "dashboard#index"
end
