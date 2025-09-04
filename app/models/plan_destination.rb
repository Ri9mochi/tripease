class PlanDestination < ApplicationRecord
  belongs_to :travel_plan
  belongs_to :destination
end
