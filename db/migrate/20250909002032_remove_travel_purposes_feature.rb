class RemoveTravelPurposesFeature < ActiveRecord::Migration[7.1]
  def up
    # 1) travel_plans の FK/Index/カラム を安全に削除
    if foreign_key_exists?(:travel_plans, :travel_purposes)
      remove_foreign_key :travel_plans, :travel_purposes
    end
    if index_exists?(:travel_plans, :travel_purpose_id)
      remove_index :travel_plans, :travel_purpose_id
    end
    if column_exists?(:travel_plans, :travel_purpose_id)
      remove_column :travel_plans, :travel_purpose_id
    end

    # 2) travel_purposes テーブルの index を安全に削除（存在すれば）
    if index_exists?(:travel_purposes, :name)
      remove_index :travel_purposes, :name
    end

    # 3) travel_purposes テーブルを削除
    drop_table :travel_purposes, if_exists: true
  end

  def down
    # down は“元に戻す”必要があれば実装（今回は空でOK）
  end
end
