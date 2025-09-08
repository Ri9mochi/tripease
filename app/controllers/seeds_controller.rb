# app/controllers/seeds_controller.rb
class SeedsController < ApplicationController
  http_basic_authenticate_with name: ENV["BASIC_AUTH_USER"], password: ENV["BASIC_AUTH_PASSWORD"]

  def run
    if PrefectureGroup.exists? || Destination.exists?
      render plain: "Already seeded", status: :ok
    else
      load Rails.root.join("db/seeds.rb")
      render plain: "Seeded!", status: :ok
    end
  end
end
