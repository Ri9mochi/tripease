class TravelPurpose < ApplicationRecord
  has_many :travel_plans, dependent: :restrict_with_exception

  validates :name, presence: true, uniqueness: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end