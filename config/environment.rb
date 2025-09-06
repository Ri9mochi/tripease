# Load the Rails application.
require_relative "application"

# Initialize the Rails application.
Rails.application.initialize!

# public/ 配下の静的ファイル配信を ENV で制御
config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

# Sprockets の推奨設定（Importmap + Sprockets の標準）
config.assets.compile = false
