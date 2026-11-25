# The base controller of the admin web UI (ActiveAdmin). With the bypass on
# (WarpLocal.admin_bypass?) it signs in the LocalAdmin user by itself.
class ApplicationController < ActionController::Base
  private

  def authenticate_admin_user!
    return super unless WarpLocal.admin_bypass?

    sign_in(:admin_user, LocalAdmin.user) unless admin_user_signed_in?
  end
end
