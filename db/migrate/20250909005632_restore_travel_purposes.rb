class RestoreTravelPurposes < ActiveRecord::Migration[7.1]
  def up
    return if table_exists?(:travel_purposes)

    create_table :travel_purposes do |t|
      t.string  :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :travel_purposes, :name, unique: true
  end

  def down
    drop_table :travel_purposes, if_exists: true
  end
end
