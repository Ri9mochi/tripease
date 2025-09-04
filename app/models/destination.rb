class Destination < ApplicationRecord
  belongs_to :prefecture_group
  has_many :plan_destinations
  has_many :travel_plans, through: :plan_destinations

  validates :name, presence: true, uniqueness: true
end
