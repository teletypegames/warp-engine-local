return unless WarpLocal.admin?

Devise.setup do |config|
  require "devise/orm/active_record"

  config.mailer_sender = "admin@local"
  config.case_insensitive_keys = [ :email ]
  config.strip_whitespace_keys = [ :email ]
  config.skip_session_storage = [ :http_auth ]
  config.stretches = 10
  config.password_length = 6..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/
  config.sign_out_via = :delete
end
