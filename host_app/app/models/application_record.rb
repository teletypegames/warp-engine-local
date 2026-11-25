# The abstract base of the host application's models.
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
