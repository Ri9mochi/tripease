# app/controllers/travel_plans_controller.rb
require 'faraday'
require 'json'
require 'net/http'
require 'uri'

class TravelPlansController < ApplicationController
  def index
    @travel_plans = current_user.travel_plans
  end

  def new
    @travel_plan = TravelPlan.new
    @prefecture_groups = PrefectureGroup.all
    @destinations = Destination.all.order(:name)
  end

  def create
    @travel_plan = current_user.travel_plans.build(travel_plan_params)
    @travel_plan.destination_ids = params[:travel_plan][:destination_ids] if params[:travel_plan][:destination_ids].present?

    if @travel_plan.save
      redirect_to @travel_plan, notice: '旅行プランの作成に成功しました。'
    else
      @destinations = Destination.all.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @travel_plan = TravelPlan.find(params[:id])
  end

  def generate_ai
    tp_params = params.dig(:travel_plan) || {}
    destination_ids = tp_params[:destination_ids].to_a.compact_blank
    destinations = Destination.where(id: destination_ids).pluck(:name).join(', ')
    start_date   = tp_params[:start_date]
    end_date     = tp_params[:end_date]
    budget       = tp_params[:budget]
    notes        = tp_params[:notes]

    prompt_text = generate_prompt(destinations, start_date, end_date, budget, notes)

    begin
      @ai_plans = call_gemini_api(prompt_text)
      respond_to do |format|
        format.js { render 'generate_ai' }
      end
    rescue => e
      Rails.logger.error("AI生成エラー: #{e.message}")
      render js: "alert('AIによるプラン生成中にエラーが発生しました。');"
    end
  end

  def preview
    plan_data_json = Base64.strict_decode64(params[:plan_data])
    @ai_plan = JSON.parse(plan_data_json).with_indifferent_access
  end

  private

  def travel_plan_params
    params.require(:travel_plan).permit(:name, :start_date, :end_date, :budget, :notes, destination_ids: [])
  end

  # --- Google Gemini API呼び出し（Faraday版） ---
  def call_gemini_api(prompt_text)
    Rails.logger.debug("--- AI API呼び出し開始 ---")

    url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"

    conn = Faraday.new(url: url) do |f|
      f.request :json
      f.response :json
    end

    body = {
      contents: [
        {
          role: "user",
          parts: [
            { text: prompt_text }
          ]
        }
      ]
    }

    response = conn.post do |req|
      req.url "?key=#{ENV['GEMINI_API_KEY']}"
      req.headers['Content-Type'] = 'application/json'
      req.body = body.to_json
    end

    Rails.logger.debug("Gemini raw response: #{response.body.inspect}")

    json_string = response.body.dig("candidates", 0, "content", "parts", 0, "text")

    if json_string.blank?
      Rails.logger.error("Gemini APIからのtextが取得できません。レスポンス: #{response.body.inspect}")
      return []
    end

    # コードブロック除去
    cleaned_json = json_string.gsub(/```json\s*/i, '').gsub(/```/, '').strip

    JSON.parse(cleaned_json)
  rescue JSON::ParserError => e
    Rails.logger.error("Gemini APIの応答がJSONとして解析できません: #{e.message}")
    []
  rescue => e
    Rails.logger.error("Gemini API呼び出しエラー: #{e.message}")
    []
  end

  # --- プロンプト生成 ---
  def generate_prompt(destinations, start_date, end_date, budget, notes)
    <<~PROMPT
      あなたは旅行プランナーです。以下の条件に基づいて、旅行プランを必ず2案提案してください。
      提案は日本語で行い、以下のJSON形式で厳密に返答してください。JSON以外の文章は一切含めないでください。

      条件：
      - 行き先: #{destinations}
      - 期間: #{start_date} から #{end_date}
      - 予算: #{budget}円
      - その他ニーズ: #{notes}

      出力形式:
      [
        {
          "plan_name": "提案1のプラン名",
          "itinerary": [
            {
              "day": 1,
              "date": "#{start_date}",
              "place": "訪問地",
              "morning_activity": "午前中の予定",
              "lunch_restaurant": "昼食の場所",
              "afternoon_activity": "午後の予定",
              "dinner_restaurant": "夕食の場所",
              "stay_hotel": "宿泊先"
            }
          ]
        },
        {
          "plan_name": "提案2のプラン名",
          "itinerary": [
            {
              "day": 1,
              "date": "#{start_date}",
              "place": "訪問地",
              "morning_activity": "午前中の予定",
              "lunch_restaurant": "昼食の場所",
              "afternoon_activity": "午後の予定",
              "dinner_restaurant": "夕食の場所",
              "stay_hotel": "宿泊先"
            }
          ]
        }
      ]
    PROMPT
  end
end
