REGISTRY = ENV.fetch("WARP_REGISTRY", "git.teletypegames.org/build")
TOOLING_HOST = ENV.fetch("WARP_TOOLING_HOST", "https://git.teletypegames.org")
IMAGES = ENV.fetch("WARP_IMAGES", "2026.11.18")

BUILDERS = {
  godot:      "#{REGISTRY}/godot-builder:#{IMAGES}",
  phaser:     "#{REGISTRY}/phaser-builder:#{IMAGES}",
  love:       "#{REGISTRY}/love-builder:#{IMAGES}",
  bevy:       "#{REGISTRY}/bevy-builder:#{IMAGES}",
  c64:        "#{REGISTRY}/c64-builder:#{IMAGES}",
  plus4:      "#{REGISTRY}/plus4-builder:#{IMAGES}",
  ebitengine: "#{REGISTRY}/ebitengine-builder:#{IMAGES}",
  tic80:      "#{REGISTRY}/tic80pro:#{IMAGES}",
  dos:        "#{REGISTRY}/dos-builder:#{IMAGES}",
  electron:   "#{REGISTRY}/electron-builder:#{IMAGES}"
}.freeze

TOOLING = {
  tic80:      { template: "build/tic80-tools" },
  ebitengine: { template: "build/ebitengine-tools", demo: "demos/ebitengine-demo" },
  love:       { template: "build/love-tools",       demo: "demos/love-demo" },
  c64:        { template: "build/c64-tools" },
  plus4:      { template: "build/plus4-build",      demo: "demos/plus4-demo" },
  godot:      { template: "build/godot-tools",      demo: "demos/pong" },
  bevy:       { template: "build/bevy-tools",       demo: "demos/bevy-demo" },
  phaser:     { template: "build/phaser-tools",     demo: "demos/phaser-demo" },
  dos:        { template: "build/dos-tools" },
  electron:   { template: "build/electron-tools",   demo: "stores/warp-engine-client" }
}.freeze

Rails.application.config.to_prepare do
  WarpEngine.configure do
    profile :local
    site_url "http://localhost:#{WarpLocal.port}"
    store_name ENV.fetch("STORE_NAME", "Local")
    sync_target WarpLocal.sync_target
    file_container_path WarpLocal.data_path("softwares")
    update_secret WarpLocal.secret("update_secret")
    application_tokens from: :database, owner: "Owner"
    image_class "Image"
    ci :woodpecker do
      update_server "http://localhost:#{WarpLocal.port}"
      BUILDERS.each { |platform, image| platform platform, builder: image }
    end

    runtime :emulatorjs, version: "4.2.3"

    TOOLING.each do |platform, repos|
      platform_tooling platform, **repos.transform_values { |path| "#{TOOLING_HOST}/#{path}" }, ref: "master"
    end

    admin_api do
      enable
    end

    sync do
      outbound do
        enabled true
        allowed_channels %w[stable beta dev]
      end
    end
  end
end
