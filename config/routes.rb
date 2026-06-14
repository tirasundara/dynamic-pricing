Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      get '/pricing', to: 'pricing#index'
    end
  end

  # Diagnostic endpoint for quick inspection.
  # No auth; in production this would be network-restricted rather than publicly exposed.
  get '/internal/stats', to: 'internal/stats#show'
end
