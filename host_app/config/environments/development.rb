Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.active_record.migration_error = :page_load
  config.action_mailer.default_url_options = { host: "localhost", port: WarpLocal.port }
  config.assets.debug = true if WarpLocal.admin?
end
