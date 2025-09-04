class CreateTravelPlans < ActiveRecord::Migration[7.1]
  def change
    create_table :travel_plans do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.integer :budget
      t.text :notes
      t.string :status, default: "draft"

      t.timestamps
    end
  end
end
