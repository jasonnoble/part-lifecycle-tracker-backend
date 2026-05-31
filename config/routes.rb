Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :parts, param: :part_number, only: %i[index show create update] do
    member do
      post :status, action: :update_status
      get "bom", to: "bom_items#index"
      post "bom", to: "bom_items#create"
      delete "bom/:bom_item_id", to: "bom_items#destroy"
    end
  end

  # OpenAPI viewer (development only). The spec is generated from request specs
  # via `OPENAPI=1 bundle exec rspec`; see doc/openapi.yaml.
  if Rails.env.development?
    get "/api-docs", to: "api_docs#index"
    get "/api-docs/openapi.yaml", to: "api_docs#spec"
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
