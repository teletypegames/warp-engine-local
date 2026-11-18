# The sign-in of the admin web UI: created the first time the admin is turned
# on, with a random password written to admin.json in the data folder.
module LocalAdmin
  EMAIL = "admin@local".freeze

  module_function

  # Creates the admin user when there is none; returns the sign-in Hash.
  def ensure!
    path = WarpLocal.data_path(WarpLocal::ADMIN_FILE)
    return JSON.parse(File.read(path)) if File.exist?(path) && AdminUser.exists?(email: EMAIL)

    password = SecureRandom.alphanumeric(16)
    user = AdminUser.find_or_initialize_by(email: EMAIL)
    user.update!(password: password, password_confirmation: password)
    sign_in = { "email" => EMAIL, "password" => password, "url" => "http://localhost:#{WarpLocal.port}/admin" }
    WarpLocal.write_private(WarpLocal::ADMIN_FILE, JSON.pretty_generate(sign_in))
    sign_in
  end
end
