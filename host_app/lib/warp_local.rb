require "json"
require "securerandom"
require "fileutils"

# What the local engine reads from its environment and its data folder, before
# Rails and after: the port, the data folder, whether the admin web UI is on
# (and whether it signs you in by itself),
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

  # The port the engine listens on: +PORT+, by default 7470.
  def port = Integer(ENV.fetch("PORT", "7470"))

  # The data folder: +WARP_DATA+, by default <tt>/data</tt>.
  def data_dir = ENV.fetch("WARP_DATA", "/data")

  # The path of +parts+ inside the data folder.
  def data_path(*parts) = File.join(data_dir, *parts)

  # Whether the admin web UI is on (+WARP_ADMIN+).
  def admin? = flag?("WARP_ADMIN")

  # Whether the admin web UI signs you in by itself (+WARP_ADMIN_BYPASS+,
  # only with the admin on).
  def admin_bypass? = admin? && flag?("WARP_ADMIN_BYPASS")

  # Whether the environment variable +name+ is set to 1, true, on or yes.
  def flag?(name) = %w[1 true on yes].include?(ENV.fetch(name, "0").downcase)

  # The peer the engine syncs its catalog to (+WARP_SYNC_TARGET+), or +nil+
  # when it is empty, +none+ or <tt>-</tt>.
  def sync_target
    value = ENV.fetch("WARP_SYNC_TARGET", DEFAULT_SYNC_TARGET).strip
    value.empty? || %w[none -].include?(value) ? nil : value
  end

  # The generated secret +name+ from SECRETS_FILE; a missing one is made
  # (128 hex digits) and written to the file.
  def secret(name)
    secrets = File.exist?(data_path(SECRETS_FILE)) ? JSON.parse(File.read(data_path(SECRETS_FILE))) : {}
    return secrets[name] if secrets[name]

    secrets[name] = SecureRandom.hex(64)
    write_private(SECRETS_FILE, JSON.pretty_generate(secrets))
    secrets[name]
  end

  # Writes +content+ to +name+ in the data folder, readable by the owner
  # only (0600), and returns the path.
  def write_private(name, content)
    FileUtils.mkdir_p(data_dir)
    path = data_path(name)
    File.write(path, content)
    File.chmod(0o600, path)
    path
  end
end
