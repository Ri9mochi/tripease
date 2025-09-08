# config/importmap.rb
pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@rails/ujs",            to: "@rails--ujs.js"
pin "destination_filter",    to: "destination_filter.js", preload: true
