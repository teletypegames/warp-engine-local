# The token the developer tools sign in with: every scope, written to the
# token file in the data folder. A token file whose token no longer works is
# replaced.
module LocalToken
  NAME = "Local token (token file)".freeze

  SCOPES = [ WarpEngine::ApplicationToken::UPDATE_SCOPE, WarpEngine::ApplicationToken::UPLOAD_SCOPE,
             *WarpEngine::ApplicationToken::ADMIN_SCOPES ].freeze

  module_function

  # Returns the plain token of the file, issuing a new one when the file is
  # missing or its token is not active.
  def ensure!(owner)
    path = WarpLocal.data_path(WarpLocal::TOKEN_FILE)
    current = File.exist?(path) ? File.read(path).strip : ""
    return current if current.present? && WarpEngine::ApplicationToken.authenticate(current)

    token = WarpEngine::ApplicationToken.create!(name: NAME, owner: owner, scopes: SCOPES, unrestricted: true)
    WarpLocal.write_private(WarpLocal::TOKEN_FILE, "#{token.plain_token}\n")
    token.plain_token
  end

  # Revokes every token-file token, so the next ensure! issues a new one.
  def revoke_all!(owner)
    WarpEngine::ApplicationToken.kept.where(owner: owner, name: NAME).find_each(&:revoke!)
  end
end
