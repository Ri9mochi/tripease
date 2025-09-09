class CreateTravelPurposes < ActiveRecord::Migration[7.1]
  class MxTravelPurpose < ApplicationRecord
    self.table_name = "travel_purposes"
    validates :name, presence: true, uniqueness: true
  end

  def up
    create_table :travel_purposes, if_not_exists: true do |t|
      t.string  :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :travel_purposes, :name, unique: true unless index_exists?(:travel_purposes, :name)

    # 初期データ
    MxTravelPurpose.reset_column_information
    %w[家族旅行 社員旅行 デート 一人旅 友人旅行 卒業旅行 その他].each_with_index do |n, i|
      MxTravelPurpose.find_or_create_by!(name: n) { |tp| tp.position = i }
    end
  end

  def down
    # ← ここが今回の肝。 index があれば外す（if_exists か index_exists? ガード）
    remove_index :travel_purposes, :name if index_exists?(:travel_purposes, :name)

    # 外部キーは “AddTravelPurposeToTravelPlans” が down なので今は無い想定
    drop_table :travel_purposes, if_exists: true
  end
end
