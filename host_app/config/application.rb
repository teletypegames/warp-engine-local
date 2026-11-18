require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"

require_relative "../lib/warp_local"
require "sprockets/railtie" if WarpLocal.admin?

Bundler.require(*Rails.groups, *(WarpLocal.admin? ? [ :admin ] : []))
require "warp_engine"

module HostApp
  class Application < Rails::Application
    config.load_defaults 8.1
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc
    config.hosts.clear
    config.secret_key_base = WarpLocal.secret("secret_key_base")
    config.active_job.queue_adapter = :solid_queue
    config.solid_queue.connects_to = { database: { writing: :queue } }
    config.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))
    config.log_level = ENV.fetch("LOG_LEVEL", "info")

    initializer "warp_local.admin_dir", before: :setup_main_autoloader do
      Rails.autoloaders.main.ignore(Rails.root.join("app/admin"))
      Rails.autoloaders.main.ignore(Rails.root.join("app/models/admin_user.rb")) unless WarpLocal.admin?
    end
  end
end
