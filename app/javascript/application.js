import "@hotwired/turbo-rails"
import Rails from "@rails/ujs"
Rails.start()

// Stimulusは使わないのでcontrollersの読み込み削除
import "./destination_filter"
