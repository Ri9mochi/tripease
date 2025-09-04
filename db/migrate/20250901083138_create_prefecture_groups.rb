class CreatePrefectureGroups < ActiveRecord::Migration[7.1]
  def change
    create_table :prefecture_groups do |t|
      t.string :name, null: false
      t.timestamps
    end
  end
end
