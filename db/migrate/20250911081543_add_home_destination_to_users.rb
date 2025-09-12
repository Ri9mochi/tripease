class AddHomeDestinationToUsers < ActiveRecord::Migration[7.1]
  def up
    # 1) カラムが無ければ追加（NULL許可）
    unless column_exists?(:users, :home_destination_id)
      add_column :users, :home_destination_id, :bigint, null: true
    end

    adapter = ActiveRecord::Base.connection.adapter_name.downcase

    # 2) NOT NULL/デフォルト0 を先に解除（ここがポイント）
    if adapter == "mysql2"
      # MySQL: 型は BIGINT に合わせて NULL/DEFAULT NULL を明示
      execute <<~SQL
        ALTER TABLE users
        MODIFY home_destination_id BIGINT NULL DEFAULT NULL
      SQL
    else
      # SQLite / PostgreSQL など
      change_column_null    :users, :home_destination_id, true
      begin
        change_column_default :users, :home_destination_id, from: 0, to: nil
      rescue
        # すでにデフォルトが無い等のケースは無視
      end
    end

    # 3) インデックスを、無ければ追加
    add_index :users, :home_destination_id unless index_exists?(:users, :home_destination_id)

    # 4) データクレンジング（不整合は NULL へ）
    if adapter == "mysql2"
      # 0 を NULL に
      execute "UPDATE users SET home_destination_id = NULL WHERE home_destination_id = 0"

      # destinations に存在しない ID を NULL に
      execute <<~SQL
        UPDATE users u
        LEFT JOIN destinations d ON u.home_destination_id = d.id
        SET u.home_destination_id = NULL
        WHERE u.home_destination_id IS NOT NULL
          AND d.id IS NULL
      SQL
    else
      execute <<~SQL
        UPDATE users
        SET home_destination_id = NULL
        WHERE home_destination_id IS NOT NULL
          AND home_destination_id NOT IN (SELECT id FROM destinations)
      SQL
    end

    # 5) 外部キー追加（無ければ）。削除時は NULL にする方針が安全
    unless foreign_key_exists?(:users, :destinations, column: :home_destination_id)
      add_foreign_key :users, :destinations, column: :home_destination_id, on_delete: :nullify
    end
  end

  def down
    # 逆順で除去（存在チェック付き）
    if foreign_key_exists?(:users, :destinations, column: :home_destination_id)
      remove_foreign_key :users, column: :home_destination_id
    end
    remove_index  :users, :home_destination_id if index_exists?(:users, :home_destination_id)
    remove_column :users, :home_destination_id  if column_exists?(:users, :home_destination_id)
  end
end
