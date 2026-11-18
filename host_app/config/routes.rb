Rails.application.routes.draw do
  if WarpLocal.admin?
    devise_for :admin_users, ActiveAdmin::Devise.config
    ActiveAdmin.routes(self)
  end

  root to: "home#show"

  namespace :api do
    get "image/:id", to: "images#show"
  end

  mount WarpEngine::Engine => "/"
end
