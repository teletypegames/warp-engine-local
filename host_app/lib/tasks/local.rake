namespace :local do
  desc "First boot and every boot after: the owner, the token file, and the admin sign-in when the admin is on"
  task bootstrap: :environment do
    owner = Owner.local
    LocalToken.ensure!(owner)
    LocalAdmin.ensure! if WarpLocal.admin?
  end

  desc "Prints the token the developer tools sign in with (RESET=1 issues a new one)"
  task token: :environment do
    owner = Owner.local
    LocalToken.revoke_all!(owner) if ENV["RESET"] == "1"
    puts LocalToken.ensure!(owner)
  end
end
