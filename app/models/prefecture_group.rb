class PrefectureGroup < ApplicationRecord
  has_many :destinations, dependent: :destroy
end
