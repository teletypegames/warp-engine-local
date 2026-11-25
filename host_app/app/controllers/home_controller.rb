# The root of a headless engine: the same answer as /.well-known/warp-engine,
# so a browser opened on the port tells what runs there.
class HomeController < ActionController::API
  # <tt>GET /</tt>: redirects to <tt>/.well-known/warp-engine</tt>.
  def show
    redirect_to "/.well-known/warp-engine"
  end
end
