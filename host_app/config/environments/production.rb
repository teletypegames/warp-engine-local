Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.public_file_server.enabled = true
  config.force_ssl = false
  config.active_record.dump_schema_after_migration = false
  config.action_mailer.default_url_options = { host: "localhost", port: WarpLocal.port }
  if WarpLocal.admin?
    config.assets.compile = true
    config.assets.digest = true
  end
end
