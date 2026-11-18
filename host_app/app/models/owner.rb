# The one owner of this machine's tokens: the developer. The local engine has
# no users; its token file and the tokens it issues belong to this record.
class Owner < ApplicationRecord
  validates :name, presence: true

  # Returns the owner, creating it on first use.
  def self.local = first_or_create!(name: "Local")
end
