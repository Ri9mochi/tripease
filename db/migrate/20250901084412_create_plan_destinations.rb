class CreatePlanDestinations < ActiveRecord::Migration[7.1]
  def change
    create_table :plan_destinations do |t|
      t.references :travel_plan, null: false, foreign_key: true
      t.references :destination, null: false, foreign_key: true
      t.timestamps
    end
  end
end
