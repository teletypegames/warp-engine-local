require "json"
require "securerandom"
require "fileutils"

# What the local engine reads from its environment and its data folder, before
# Rails and after: the port, the data folder, whether the admin web UI is on,
# the sync target, and the secrets generated on first boot.
module WarpLocal
  # The token file the developer tools read (WarpEngine Toolbox).
  TOKEN_FILE = "local-token".freeze
  # The generated secrets (secret_key_base, update_secret).
  SECRETS_FILE = "secrets.json".freeze
  # The admin web UI sign-in, written when the admin is first turned on.
  ADMIN_FILE = "admin.json".freeze
  # The sync target when none is given.
  DEFAULT_SYNC_TARGET = "none".freeze

  module_function

  def port = Integer(ENV.fetch("PORT", "7470"))

  def data_dir = ENV.fetch("WARP_DATA", "/data")

  def data_path(*parts) = File.join(data_dir, *parts)

  def admin? = %w[1 true on yes].include?(ENV.fetch("WARP_ADMIN", "0").downcase)

  def sync_target
    value = ENV.fetch("WARP_SYNC_TARGET", DEFAULT_SYNC_TARGET).strip
    value.empty? || %w[none -].include?(value) ? nil : value
  end

  def secret(name)
    secrets = File.exist?(data_path(SECRETS_FILE)) ? JSON.parse(File.read(data_path(SECRETS_FILE))) : {}
    return secrets[name] if secrets[name]

    secrets[name] = SecureRandom.hex(64)
    write_private(SECRETS_FILE, JSON.pretty_generate(secrets))
    secrets[name]
  end

  def write_private(name, content)
    FileUtils.mkdir_p(data_dir)
    path = data_path(name)
    File.write(path, content)
    File.chmod(0o600, path)
    path
  end
end
