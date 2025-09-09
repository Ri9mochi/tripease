require 'faraday'
require 'json'
require 'net/http'
require 'uri'

class TravelPlansController < ApplicationController
  def index
    # 目的名のN+1回避（お好みで）
    @travel_plans = current_user.travel_plans.includes(:travel_purpose)
  end

  def new
    @travel_plan = TravelPlan.new
    @prefecture_groups = PrefectureGroup.all
    @destinations = Destination.all.order(:name)
    @travel_purposes = TravelPurpose.order(:position, :id)  # ← 追加
  end

  def create
    # AIプランからのデータがあるかチェック
    itinerary_data = params[:itinerary_json]

    if itinerary_data.present?
      # フォームから目的IDも受け取る
      tp = params.fetch(:travel_plan, {}).permit(:travel_purpose_id, :budget, :notes)

      @travel_plan = current_user.travel_plans.build(
        name:       params[:name],
        start_date: params[:start_date],
        end_date:   params[:end_date],
        itinerary:  JSON.parse(itinerary_data),
        travel_purpose_id: tp[:travel_purpose_id]               # ← 追加
      )
      # 予算やメモもAI経由で保持したい場合は下記も付けられます
      @travel_plan.budget = tp[:budget] if tp[:budget].present?
      @travel_plan.notes  = tp[:notes]  if tp[:notes].present?
    else
      # 通常のフォームからの作成処理（目的ID・行き先を許可済み）
      @travel_plan = current_user.travel_plans.build(travel_plan_params)
    end
    
    if @travel_plan.save
      redirect_to authenticated_root_path, notice: '旅行プランがマイプランに保存されました。'
    else
      flash[:alert] = 'プランの保存に失敗しました。'
      # newの再表示に必要なマスタを再ロード
      @prefecture_groups = PrefectureGroup.all
      @destinations = Destination.all.order(:name)
      @travel_purposes = TravelPurpose.order(:position, :id)
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @travel_plan = TravelPlan.find(params[:id])
  end

  def edit
    @travel_plan = TravelPlan.find(params[:id])
    @prefecture_groups = PrefectureGroup.all
    @destinations = Destination.all.order(:name)
    @travel_purposes = TravelPurpose.order(:position, :id)  # ← 追加
  end

  def update
    @travel_plan = TravelPlan.find(params[:id])
    if @travel_plan.update(travel_plan_params)
      redirect_to @travel_plan, notice: '旅行プランが更新されました。'
    else
      @prefecture_groups = PrefectureGroup.all
      @destinations = Destination.all.order(:name)
      @travel_purposes = TravelPurpose.order(:position, :id)  # ← 追加
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @travel_plan = TravelPlan.find(params[:id])
    @travel_plan.destroy
    redirect_to authenticated_root_path, notice: '旅行プランを削除しました。'
  end

  def generate_ai
    tp_params = params.dig(:travel_plan) || {}
    destination_ids = tp_params[:destination_ids].to_a.compact_blank
    destinations_names = Destination.where(id: destination_ids).pluck(:name).join(', ')
    start_date = tp_params[:start_date]
    end_date = tp_params[:end_date]
    budget = tp_params[:budget]
    notes = tp_params[:notes]
    
    # 期間を計算（nilガード）
    if start_date.present? && end_date.present?
      num_days = (Date.parse(end_date) - Date.parse(start_date)).to_i + 1
    else
      num_days = 1
    end

    prompt_text = generate_prompt(destinations_names, start_date, end_date, budget, notes, num_days)

    begin
      @ai_plans = call_gemini_api(prompt_text)

      cache_key = "ai_plans_for_user_#{current_user.id}"
      Rails.cache.write(cache_key, @ai_plans, expires_in: 1.hour)

      respond_to do |format|
        format.js { render 'generate_ai' }
      end
    rescue => e
      Rails.logger.error("AI生成エラー: #{e.message}")
      render js: "alert('AIによるプラン生成中にエラーが発生しました。時間を置いて再度お試しください。');"
    end
  end

  def preview
    cache_key = "ai_plans_for_user_#{current_user.id}"
    @ai_plans = Rails.cache.read(cache_key)

    unless @ai_plans.present?
      flash[:error] = "プランデータが見つかりませんでした。もう一度プランを作成してください。"
      redirect_to new_travel_plan_path
      return
    end

    plan_index = params[:plan_index].to_i
  
    if plan_index < 0 || plan_index >= @ai_plans.length
      flash[:error] = "指定されたプランが見つかりません。"
      redirect_to new_travel_plan_path
      return
    end

    @ai_plan = @ai_plans[plan_index]
  end

  private

  def travel_plan_params
    params.require(:travel_plan).permit(
      :name, :start_date, :end_date, :budget, :notes, :status,
      :travel_purpose_id,           # ← 追加：目的を受け取る
      destination_ids: []           # 既存：行き先（多対多）
    )
  end

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

  def generate_prompt(destinations_names, start_date, end_date, budget, notes, num_days)
    <<~PROMPT
      あなたは旅行プランを提案するAIアシスタントです。
      ユーザーの旅行ニーズに基づいて、#{num_days}日間の旅行プランを2案提案してください。

      **出力形式の厳守:**
      あなたの回答は、以下のJSON形式で出力してください。
      ```json
      [
        {
          "plan_name": "提案プラン1のタイトル",
          "itinerary": [
            {
              "day": 1,
              "date": "YYYY-MM-DD",
              "place": "行き先の地名",
              "morning_activity": "午前の活動内容",
              "lunch_restaurant": "昼食の店名",
              "lunch_restaurant_url": "昼食の予約URL（例: 食べログ、公式HPなど）",
              "afternoon_activity": "午後の活動内容",
              "dinner_restaurant": "夕食の店名",
              "dinner_restaurant_url": "夕食の予約URL（例: 食べログ、公式HPなど）",
              "stay_hotel": "宿泊ホテルの具体的な名前",
              "stay_hotel_url": "宿泊ホテルの予約URL（例: 楽天トラベル、公式HPなど）"
            },
            // ... 2日目以降のデータ ...
          ]
        },
        // ... 2案目のデータ ...
      ]
      ```

      **追加の要望:**
      - **レストランとホテルは具体的な店名・ホテル名を提案し、その予約URL（例: 楽天トラベル、じゃらん、食べログ、公式ホームページなど）も必ず含めてください。**
      - AIがURLを生成できない場合は、URLフィールドを空の文字列にしてください。
      - ユーザーの希望に沿った、魅力的なプランを提案してください。

      **ユーザーの旅行情報:**
      - 旅行名: #{travel_plan_params[:name]}
      - 行き先: #{destinations_names}
      - 期間: #{start_date} から #{end_date} までの#{num_days}日間
      - 予算: #{budget}円
      - その他ニーズ: #{notes}
    PROMPT
  end
end