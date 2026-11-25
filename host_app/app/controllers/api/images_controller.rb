# The JSON API of the host application, beside the engine's own.
module Api
  # Serves the catalog's images (Image) to the clients: <tt>GET /api/image/:id</tt>.
  # A missing record or file answers 404 with <tt>{ "error": "Not found" }</tt>.
  class ImagesController < ActionController::API
    rescue_from ActiveRecord::RecordNotFound do
      render json: { error: "Not found" }, status: :not_found
    end

    rescue_from Errno::ENOENT do
      render json: { error: "Not found" }, status: :not_found
    end

    # <tt>GET /api/image/:id</tt>: sends the file of the Image inline with its
    # content type; 404 when the record or the file is missing.
    def show
      image = Image.find(params[:id])
      send_file image.file_path, type: image.content_type, disposition: "inline"
    end
  end
end
