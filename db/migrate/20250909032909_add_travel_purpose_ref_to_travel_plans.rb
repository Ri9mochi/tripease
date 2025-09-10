class AddTravelPurposeRefToTravelPlans < ActiveRecord::Migration[7.1]
  def change
    add_reference :travel_plans, :travel_purpose, null: true, foreign_key: true, index: true
  end
end
