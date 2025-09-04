class CreateDestinations < ActiveRecord::Migration[7.1]
  def change
    create_table :destinations do |t|
      t.references :prefecture_group, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
    # ここにインデックスを追加
    add_index :destinations, :name, unique: true
  end
end
