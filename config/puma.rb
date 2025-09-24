# 環境
environment ENV.fetch("RACK_ENV") { ENV.fetch("RAILS_ENV", "development") }

# Render では必ず PORT を listen する
port ENV.fetch("PORT") { 3000 }

# メモリ安全寄りの設定（Small/Freeでも安定）
workers ENV.fetch("WEB_CONCURRENCY", 1).to_i
threads_count = ENV.fetch("RAILS_MAX_THREADS", 5).to_i
threads threads_count, threads_count

preload_app!

# tmp/restart.txt で再起動可
plugin :tmp_restart

on_worker_boot do
  # フォーク後にDB再接続
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

# 開発環境のタイムアウト
worker_timeout 3600 if ENV.fetch("RAILS_ENV", "development") == "development"
