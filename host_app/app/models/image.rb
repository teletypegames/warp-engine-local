# An image of the catalog (a screenshot or a cover), uploaded in the admin web
# UI and kept as a file under Image.upload_path; WarpEngine::SoftwareImage
# links it to a software. Soft-deleted records (+deleted_at+) are hidden.
class Image < ApplicationRecord
  # The folder the image files are stored in: +IMAGE_CONTAINER_PATH+, by
  # default <tt>/images</tt>.
  def self.upload_path
    ENV.fetch("IMAGE_CONTAINER_PATH", "/images")
  end

  has_many :software_images, class_name: "WarpEngine::SoftwareImage", dependent: :restrict_with_error

  default_scope { where(deleted_at: nil) }

  # The uploaded file of the admin form; saving the record names it with a
  # UUID and copies it under Image.upload_path.
  attr_accessor :file_upload

  before_validation :assign_upload_attributes, if: -> { file_upload.present? }
  after_commit :store_upload_file, on: [ :create, :update ], if: -> { file_upload.present? }

  # The attributes the admin's filters may search on (Ransack).
  def self.ransackable_attributes(auth_object = nil)
    %w[content_type created_at deleted_at filename id original_filename updated_at]
  end

  # The path of the image file on disk.
  def file_path
    File.join(self.class.upload_path, filename.to_s)
  end

  # The URL the clients load the image from (Api::ImagesController).
  def url = "/api/image/#{id}"

  private

  def assign_upload_attributes
    self.original_filename = file_upload.original_filename
    self.content_type      = file_upload.content_type.presence || "application/octet-stream"
    self.filename          = "#{SecureRandom.uuid}#{File.extname(file_upload.original_filename)}"
  end

  def store_upload_file
    FileUtils.mkdir_p(self.class.upload_path)
    IO.copy_stream(file_upload.to_io, file_path)
  end
end
