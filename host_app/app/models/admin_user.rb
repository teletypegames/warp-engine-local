# A sign-in of the admin web UI, there only when WARP_ADMIN=1.
class AdminUser < ApplicationRecord
  devise :database_authenticatable, :rememberable, :validatable

  # The attributes the admin's filters may search on (Ransack).
  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at email id updated_at]
  end
end
