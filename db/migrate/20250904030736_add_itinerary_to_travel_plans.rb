class AddItineraryToTravelPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :travel_plans, :itinerary, :json
  end
end
