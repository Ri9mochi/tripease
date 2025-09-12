# app/controllers/travel_plans_controller.rb
require 'faraday'
require 'json'
require 'net/http'
require 'uri'

class TravelPlansController < ApplicationController
  # devise を使っているはずなので必要なら有効化
  # before_action :authenticate_user!

  def index
    @travel_plans = current_user.travel_plans.includes(:travel_purpose) # 目的名のN+1回避
  end

  def new
    @travel_plan        = TravelPlan.new
    @prefecture_groups  = PrefectureGroup.all
    @destinations       = Destination.order(:name)
    @travel_purposes    = TravelPurpose.order(:position, :id)
  end

  def create
    itinerary_data = params[:itinerary_json]

    if itinerary_data.present?
      tp = params.fetch(:travel_plan, {}).permit(:travel_purpose_id, :budget, :notes)

      @travel_plan = current_user.travel_plans.build(
        name:       params[:name],
        start_date: params[:start_date],
        end_date:   params[:end_date],
        itinerary:  JSON.parse(itinerary_data)
      )
      @travel_plan.travel_purpose_id = tp[:travel_purpose_id] if tp[:travel_purpose_id].present?
      @travel_plan.budget            = tp[:budget]             if tp[:budget].present?
      @travel_plan.notes             = tp[:notes]              if tp[:notes].present?
    else
      @travel_plan = current_user.travel_plans.build(travel_plan_params)
    end

    if @travel_plan.save
      redirect_to authenticated_root_path, notice: '旅行プランがマイプランに保存されました。'
    else
      # 失敗理由をログ & 画面表示
      Rails.logger.warn("TravelPlan save failed: #{@travel_plan.errors.full_messages.join(', ')}")
      flash.now[:alert] = @travel_plan.errors.full_messages.join('<br>')

      @prefecture_groups = PrefectureGroup.all
      @destinations      = Destination.order(:name)
      @travel_purposes   = TravelPurpose.order(:position, :id)
      render :new, status: :unprocessable_entity
    end
end

  def show
    @travel_plan = TravelPlan.find(params[:id])
  end

  def edit
    @travel_plan       = TravelPlan.find(params[:id])
    @prefecture_groups = PrefectureGroup.all
    @destinations      = Destination.order(:name)
    @travel_purposes   = TravelPurpose.order(:position, :id)
  end

  def update
    @travel_plan = TravelPlan.find(params[:id])
    if @travel_plan.update(travel_plan_params)
      redirect_to @travel_plan, notice: '旅行プランが更新されました。'
    else
      @prefecture_groups = PrefectureGroup.all
      @destinations      = Destination.order(:name)
      @travel_purposes   = TravelPurpose.order(:position, :id)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @travel_plan = TravelPlan.find(params[:id])
    @travel_plan.destroy
    redirect_to authenticated_root_path, notice: '旅行プランを削除しました。'
  end

  def generate_ai
    tp_params         = params.dig(:travel_plan) || {}
    destination_ids   = Array(tp_params[:destination_ids]).compact_blank
    destinations_names = Destination.where(id: destination_ids).pluck(:name).join(', ')
    start_date        = tp_params[:start_date]
    end_date          = tp_params[:end_date]
    budget            = tp_params[:budget]
    notes             = tp_params[:notes]
    purpose_name      = TravelPurpose.find_by(id: tp_params[:travel_purpose_id])&.name

    # 期間（日数）
    num_days =
      if start_date.present? && end_date.present?
        (Date.parse(end_date) - Date.parse(start_date)).to_i + 1
      else
        1
      end

    prompt_text = generate_prompt(
      destinations_names, start_date, end_date, budget, notes, num_days, purpose_name
    )

    begin
      @ai_plans = call_gemini_api(prompt_text)

      # ▼ 追加：正規化・検証
      @ai_plans = normalize_ai_plans(@ai_plans)

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

  def normalize_ai_plans(plans)
    return [] unless plans.is_a?(Array)

    plans.map do |plan|
      plan = plan.deep_dup
      it = plan["itinerary"]
      if it.is_a?(Array)
        it.each do |day|
          # 1) レストランURL検証＆店名整合
          %w[lunch dinner].each do |meal|
            name_key = "#{meal}_restaurant"
            url_key  = "#{meal}_restaurant_url"
            fixed = sanitize_tabelog_pair(day[name_key], day[url_key])
            day[name_key] = fixed[:name]
            day[url_key]  = fixed[:url]
          end

          # 2) 朝食（breakfast）検証＆補完
          b_fixed = sanitize_any_pair(day["breakfast_restaurant"], day["breakfast_restaurant_url"])
          day["breakfast_restaurant"]     = b_fixed[:name]
          day["breakfast_restaurant_url"] = b_fixed[:url]

          if day["breakfast_restaurant"].blank?
            if day["stay_hotel"].present?
              day["breakfast_restaurant"]     = "ホテル朝食（#{day['stay_hotel']}）"
              day["breakfast_restaurant_url"] = day["stay_hotel_url"].to_s
            else
              day["breakfast_restaurant"]     = "朝食"
              day["breakfast_restaurant_url"] = ""
            end
          end
        end
      end
      plan
    end
  end

  # --- tabelog専用：URL正当性と店名の整合を保証 ---
  def sanitize_tabelog_pair(name, url)
    url = url.to_s.strip
    name = name.to_s.strip

    return { name: name, url: "" } if url.blank?

    uri = (URI.parse(url) rescue nil)
    return { name: name, url: "" } unless uri&.host&.end_with?("tabelog.com")

    return { name: name, url: "" } unless http_ok?(uri)

    # タイトルから店舗名を抽出して、名前を上書き（表示とURLを一致させる）
    title = fetch_title(uri)
    store = extract_tabelog_store_name(title)
    display_name = store.presence || name

    { name: display_name, url: url }
  rescue
    { name: name.to_s, url: "" }
  end

  # --- 任意ドメイン用：存在確認だけ（200でなければ空文字） ---
  def sanitize_any_pair(name, url)
    url = url.to_s.strip
    name = name.to_s.strip
    return { name: name, url: "" } if url.blank?

    uri = (URI.parse(url) rescue nil)
    return { name: name, url: "" } unless uri && %w(http https).include?(uri.scheme)
    return { name: name, url: "" } unless http_ok?(uri)

    { name: name, url: url }
  rescue
    { name: name.to_s, url: "" }
  end

  def http_ok?(uri)
    conn = Faraday.new(url: "#{uri.scheme}://#{uri.host}") do |f|
      f.options.timeout = 3
      f.options.open_timeout = 3
    end
    path = uri.request_uri.presence || "/"

    head = (conn.head(path) rescue nil)
    return true if head && head.status.to_i == 200

    get = (conn.get(path) rescue nil)
    get && get.status.to_i == 200
  end

  def fetch_title(uri)
    conn = Faraday.new(url: "#{uri.scheme}://#{uri.host}") do |f|
      f.options.timeout = 3
      f.options.open_timeout = 3
    end
    res = conn.get(uri.request_uri.presence || "/") rescue nil
    return "" unless res && res.status.to_i == 200

    html = res.body.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    html[/\<title\>(.*?)\<\/title\>/im, 1].to_s.strip
  end

  # ざっくりタイトルから店名を抜く（例: "政寿司 本店 - 食べログ" / "政寿司 本店｜食べログ"）
  def extract_tabelog_store_name(title)
    return "" if title.blank?
    t = title.dup

    # 「 - 食べログ」より前 / 「｜食べログ」より前 を優先
    if t.include?(" - 食べログ")
      return t.split(" - 食べログ").first.strip
    end
    if t.include?("｜食べログ")
      return t.split("｜食べログ").first.strip
    end

    # 保険：末尾の「食べログ」を除去
    t.sub(/食べログ\s*$/,'').strip
  end

  def preview
    cache_key = "ai_plans_for_user_#{current_user.id}"
    @ai_plans = Rails.cache.read(cache_key)

    unless @ai_plans.present?
      flash[:error] = "プランデータが見つかりませんでした。もう一度プランを作成してください。"
      redirect_to new_travel_plan_path and return
    end

    plan_index = params[:plan_index].to_i
    if plan_index < 0 || plan_index >= @ai_plans.length
      flash[:error] = "指定されたプランが見つかりません。"
      redirect_to new_travel_plan_path and return
    end

    @ai_plan = @ai_plans[plan_index]
  end

  private

  def travel_plan_params
    params.require(:travel_plan).permit(
      :name, :start_date, :end_date, :budget, :notes, :status,
      :travel_purpose_id,
      destination_ids: []
    )
  end

  # --- ここからAI呼び出し＆堅牢パーサ ---
  def call_gemini_api(prompt_text)
    Rails.logger.debug("--- AI API呼び出し開始 ---")

    url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"

    conn = Faraday.new(url: url) do |f|
      f.request  :json
      f.response :json
    end

    body = {
      contents: [
        { role: "user", parts: [ { text: prompt_text } ] }
      ],
      generationConfig: {
        response_mime_type: "application/json", # JSONのみを期待
        temperature: 0.2,   # ← 低めで安定化（0.0〜0.3あたり）
        topP: 0.5,
        topK: 40
      }
    }

    response = conn.post do |req|
      req.url "?key=#{ENV['GEMINI_API_KEY']}"
      req.headers['Content-Type'] = 'application/json'
      req.body = body.to_json
    end

    Rails.logger.debug("Gemini raw response: #{response.body.inspect}")

    json_text = response.body.dig("candidates", 0, "content", "parts", 0, "text")
    parse_ai_json(json_text)
  rescue => e
    Rails.logger.error("Gemini API呼び出しエラー: #{e.message}")
    []
  end

  # 余計な前後テキストが混じってもJSONだけ抜き出してパース
  def parse_ai_json(json_text)
    return [] if json_text.blank?

    text = json_text.to_s.strip

    # ```json ... ``` の囲いがあれば中身優先
    if (m = text.match(/```json\s*([\s\S]*?)```/i))
      text = m[1].to_s.strip
    end

    # 先頭の [ 〜 最後の ] を抽出してパース（混在テキスト対策）
    if text.include?('[') && text.include?(']')
      start  = text.index('[')
      finish = text.rindex(']')
      candidate = text[start..finish] rescue nil
      if candidate
        begin
          return JSON.parse(candidate)
        rescue JSON::ParserError
          # 続けて最後の手段へ
        end
      end
    end

    # 最後の手段：そのままパース
    JSON.parse(text)
  rescue JSON::ParserError => e
    Rails.logger.error("Gemini APIの応答がJSONとして解析できません: #{e.message}")
    []
  end
  # --- ここまで ---

  def generate_prompt(destinations_names, start_date, end_date, budget, notes, num_days, purpose_name)
    <<~PROMPT
      あなたは旅行プランを提案するAIアシスタントです。
      ユーザーの旅行ニーズに基づいて、#{num_days}日間の旅行プランを2案提案してください。

      **出力形式の厳守:**
      あなたの回答は、以下のJSON形式「だけ」を出力してください（前後の文章・注釈は禁止）。
      [
        {
          "plan_name": "提案プラン1のタイトル",
          "itinerary": [
            {
              "day": 1,
              "date": "YYYY-MM-DD",
              "place": "行き先の地名",
              "breakfast_restaurant": "朝食の店名（例: ホテル朝食）",
              "breakfast_restaurant_url": "朝食のURL（ホテル公式/食べログ等。朝食が不要な場合は空文字）",
              "morning_activity": "午前の活動内容",
              "lunch_restaurant": "昼食の店名",
              "lunch_restaurant_url": "昼食の予約URL（例: 食べログ）",
              "afternoon_activity": "午後の活動内容",
              "dinner_restaurant": "夕食の店名",
              "dinner_restaurant_url": "夕食の予約URL（例: 食べログ）",
              "stay_hotel": "宿泊ホテルの具体的な名前",
              "stay_hotel_url": "宿泊ホテルの予約URL（例:公式HP）"
            }
          ]
        }
      ]

      **追加の要望（厳守）:**
      - レストランURLは **tabelog.com** の店舗ページのみを入れてください。
      - 確実にアクセスができるURLを入れること。
      - 提示したレストラン名とURLは確実に一致させること。
      - 架空の店名や存在しないURLは生成しないでください。
      - ホテルURLは公式HPのURLを入れること。

      **出力規約（重要）**
      - 回答は **JSON配列のみ** をそのまま出力すること。
      - コードブロック（```）や注記、見出し、説明文は一切付加しないこと。

      **ユーザーの旅行情報:**
      - 旅行目的: #{purpose_name.presence || "（未指定）"}
      - 行き先: #{destinations_names.presence || "（未指定）"}
      - 期間: #{start_date.presence || "未定"} 〜 #{end_date.presence || "未定"}（#{num_days}日間想定）
      - 総予算: #{budget.presence || "未設定"} 円
      - その他ニーズ: #{notes.presence || "特になし"}
    PROMPT
  end
end
