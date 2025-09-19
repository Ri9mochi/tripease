# app/controllers/travel_plans_controller.rb
require 'faraday'
require 'json'
require 'net/http'
require 'uri'

class TravelPlansController < ApplicationController
  # 必要に応じてコメントアウトを外す
  # before_action :authenticate_user!

  # ★ 追加: show だけ専用レイアウトを使う
  layout :resolve_layout  # ★ 追加

  # ===== CRUD =====
  def index
    @travel_plans = current_user.travel_plans.includes(:travel_purpose)
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
      @travel_plan.budget            = tp[:budget]            if tp[:budget].present?
      @travel_plan.notes             = tp[:notes]             if tp[:notes].present?
    else
      @travel_plan = current_user.travel_plans.build(travel_plan_params)
    end

    if @travel_plan.save
      redirect_to authenticated_root_path, notice: '旅行プランがマイプランに保存されました。'
    else
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

  # ▼ 編集保存：itinerary_json を受理し、簡易検証のうえ保存
  def update
    @travel_plan = TravelPlan.find(params[:id])
    @travel_plan.assign_attributes(travel_plan_params)

    if params[:itinerary_json].present?
      begin
        new_itinerary = JSON.parse(params[:itinerary_json])
        unless new_itinerary.is_a?(Array)
          flash.now[:alert] = "旅程データの形式が不正です。"
          hydrate_collections_for_edit and return render(:edit, status: :unprocessable_entity)
        end

        # 食べログURLの最低限検証（昼/夜のみ必須）
        pseudo_plans = [{ "plan_name" => @travel_plan.name, "itinerary" => new_itinerary }]
        issues = collect_meal_issues(pseudo_plans)
        if issues.any?
          Rails.logger.warn("Update validation failed: #{issues.inspect}")
          flash.now[:alert] = "レストランURLの検証に失敗しました。URLや店舗を見直してください。"
          @itinerary_preview = new_itinerary
          hydrate_collections_for_edit and return render(:edit, status: :unprocessable_entity)
        end

        @travel_plan.itinerary = new_itinerary
      rescue JSON::ParserError
        flash.now[:alert] = "旅程データの読み込みに失敗しました。"
        hydrate_collections_for_edit and return render(:edit, status: :unprocessable_entity)
      end
    end

    if @travel_plan.save
      redirect_to @travel_plan, notice: '旅行プランが更新されました。'
    else
      hydrate_collections_for_edit
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @travel_plan = TravelPlan.find(params[:id])
    @travel_plan.destroy
    redirect_to authenticated_root_path, notice: '旅行プランを削除しました。'
  end

  # ===== AI 生成 → プレビュー =====
  def generate_ai
    tp_params          = params.dig(:travel_plan) || {}
    destination_ids    = Array(tp_params[:destination_ids]).compact_blank
    destinations_names = Destination.where(id: destination_ids).pluck(:name).join(', ')
    start_date         = tp_params[:start_date]
    end_date           = tp_params[:end_date]
    budget             = tp_params[:budget]
    notes              = tp_params[:notes]
    purpose_name       = TravelPurpose.find_by(id: tp_params[:travel_purpose_id])&.name

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
      @ai_plans = normalize_ai_plans(@ai_plans)

      Rails.cache.write("ai_plans_for_user_#{current_user.id}", @ai_plans, expires_in: 1.hour)

      respond_to do |format|
        format.js { render 'generate_ai' }
      end
    rescue => e
      Rails.logger.error("AI生成エラー: #{e.message}")
      render js: "alert('AIによるプラン生成中にエラーが発生しました。時間を置いて再度お試しください。');"
    end
  end

  def preview
    @ai_plans = Rails.cache.read("ai_plans_for_user_#{current_user.id}")
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

  # ★ 追加: アクションごとにレイアウト切り替え
  def resolve_layout
    # show だけ application を使わず、専用レイアウトを適用
    action_name == "show" ? "travel_plans_show" : "application"
  end

  # ===== Strong Params =====
  def travel_plan_params
    params.require(:travel_plan).permit(
      :name, :start_date, :end_date, :budget, :notes, :status,
      :travel_purpose_id,
      destination_ids: []
    )
  end

  def hydrate_collections_for_edit
    @prefecture_groups = PrefectureGroup.all
    @destinations      = Destination.order(:name)
    @travel_purposes   = TravelPurpose.order(:position, :id)
  end

  # ====== 旅程正規化（AI応答後の整備） ======
  def normalize_ai_plans(plans)
    return [] unless plans.is_a?(Array)

    plans.map do |plan|
      plan = plan.deep_dup
      it = plan["itinerary"]

      if it.is_a?(Array)
        it.each do |day|
          %w[lunch dinner].each do |meal|
            name_key = "#{meal}_restaurant"
            url_key  = "#{meal}_restaurant_url"
            fixed    = sanitize_tabelog_pair(day[name_key], day[url_key])
            day[name_key] = fixed[:name]
            day[url_key]  = fixed[:url]
          end

          b_fixed = sanitize_any_pair(day["breakfast_restaurant"], day["breakfast_restaurant_url"])
          day["breakfast_restaurant"]     = b_fixed[:name]
          day["breakfast_restaurant_url"] = b_fixed[:url]

          if day["breakfast_restaurant"].blank?
            if day["stay_hotel"].present?
              day["breakfast_restaurant"]     = "ホテル朝食（#{day['stay_hotel']}）"
              day["breakfast_restaurant_url"] = day["stay_hotel_url"].to_s
            else
              day["breakfast_restaurant"]     = "ホテル朝食"
              day["breakfast_restaurant_url"] = ""
            end
          end
        end
      end

      plan
    end
  end

  # ====== 昼/夜レストランURLの検証（編集保存時も使う） ======
  def collect_meal_issues(plans)
    issues = []
    Array(plans).each_with_index do |plan, pi|
      Array(plan["itinerary"]).each_with_index do |day, di|
        %w[lunch dinner].each do |meal|
          url = day["#{meal}_restaurant_url"].to_s.strip
          name = day["#{meal}_restaurant"].to_s.strip
          valid =
            url.present? &&
            (u = (URI.parse(url) rescue nil)) &&
            u&.host&.end_with?("tabelog.com") 
            http_ok?(u)
          issues << { plan_idx: pi, day_idx: di, meal: meal, name: name, url: url, reason: (url.blank? ? "missing_url" : "invalid_or_unreachable") } unless valid
        end
      end
    end
    issues
  end

  # ====== URLサニタイズ系 ======
  def sanitize_tabelog_pair(name, url)
    url  = url.to_s.strip
    name = name.to_s.strip
    return { name: name, url: "" } if url.blank?

    uri = (URI.parse(url) rescue nil)
    return { name: name, url: "" } unless uri&.host&.end_with?("tabelog.com")
    return { name: name, url: "" } unless http_ok?(uri)

    title = fetch_title(uri)
    store = extract_tabelog_store_name(title)
    { name: (store.presence || name), url: url }
  rescue
    { name: name, url: "" }
  end

  def sanitize_any_pair(name, url)
    url  = url.to_s.strip
    name = name.to_s.strip
    return { name: name, url: "" } if url.blank?

    uri = (URI.parse(url) rescue nil)
    return { name: name, url: "" } unless uri && %w(http https).include?(uri.scheme)
    return { name: name, url: "" } unless http_ok?(uri)

    { name: name, url: url }
  rescue
    { name: name, url: "" }
  end

  def http_ok?(uri)
    conn = Faraday.new(url: "#{uri.scheme}://#{uri.host}") do |f|
      f.options.timeout      = 3
      f.options.open_timeout = 3
    end
    path = uri.request_uri.presence || "/"

    head = (conn.head(path) rescue nil)
    return true if head && head.status.to_i.between?(200, 299)

    get = (conn.get(path) rescue nil)
    get && get.status.to_i.between?(200, 299)
  end

  def fetch_title(uri)
    conn = Faraday.new(url: "#{uri.scheme}://#{uri.host}") do |f|
      f.options.timeout      = 3
      f.options.open_timeout = 3
    end
    res = (conn.get(uri.request_uri.presence || "/") rescue nil)
    return "" unless res && res.status.to_i.between?(200, 299)

    html = res.body.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    html[/\<title\>(.*?)\<\/title\>/im, 1].to_s.strip
  end

  def extract_tabelog_store_name(title)
    return "" if title.blank?
    return title.split(" - 食べログ").first.strip if title.include?(" - 食べログ")
    return title.split("｜食べログ").first.strip  if title.include?("｜食べログ")
    title.sub(/食べログ\s*$/, '').strip
  end

  # ===== Gemini 呼び出し & 解析 =====
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
        response_mime_type: "application/json",
        temperature: 0.2,
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

    if response.body.is_a?(Hash) && response.body["error"]
      Rails.logger.warn("Gemini error: #{response.body['error'].inspect}")
      return []
    end

    json_text = response.body.dig("candidates", 0, "content", "parts", 0, "text")
    parse_ai_json(json_text)
  rescue => e
    Rails.logger.error("Gemini API呼び出しエラー: #{e.message}")
    []
  end

  def parse_ai_json(json_text)
    return [] if json_text.blank?
    text = json_text.to_s.strip

    if (m = text.match(/```json\s*([\s\S]*?)```/i))
      text = m[1].to_s.strip
    end

    if text.include?('[') && text.include?(']')
      start  = text.index('[')
      finish = text.rindex(']')
      candidate = text[start..finish] rescue nil
      return JSON.parse(candidate) if candidate
    end

    JSON.parse(text)
  rescue JSON::ParserError => e
    Rails.logger.error("Gemini APIの応答がJSONとして解析できません: #{e.message}")
    []
  end

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
              "breakfast_restaurant_url": "朝食のURL（空文字可）",
              "morning_activity": "午前の活動内容",
              "lunch_restaurant": "昼食の店名",
              "lunch_restaurant_url": "tabelog.com の店舗ページURL（必須）",
              "afternoon_activity": "午後の活動内容",
              "dinner_restaurant": "夕食の店名",
              "dinner_restaurant_url": "tabelog.com の店舗ページURL（必須）",
              "stay_hotel": "宿泊ホテルの具体的な名前",
              "stay_hotel_url": "宿泊ホテルの予約URL（例:公式HP）"
            }
          ]
        }
      ]

      **追加の要望（厳守）:**
      - レストランURLは **tabelog.com の店舗ページ**のみ。
      - 店名とURLは同一店舗に一致させること。
      - 200で到達可能なURLのみ。
      - 架空の店や無効URLは出力しないこと。

      **出力規約（重要）**
      - 回答は **JSON配列のみ** をそのまま出力すること。コードブロックや注記は一切不要。

      **ユーザーの旅行情報:**
      - 旅行目的: #{purpose_name.presence || "（未指定）"}
      - 行き先: #{destinations_names.presence || "（未指定）"}
      - 期間: #{start_date.presence || "未定"} 〜 #{end_date.presence || "未定"}（#{num_days}日間）
      - 総予算: #{budget.presence || "未設定"} 円
      - その他ニーズ: #{notes.presence || "特になし"}
    PROMPT
  end
end
