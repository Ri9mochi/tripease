# app/controllers/travel_plans_controller.rb
require 'faraday'
require 'json'
require 'uri'

class TravelPlansController < ApplicationController
  # before_action :authenticate_user!
  layout :resolve_layout

  class RateLimitExceeded < StandardError; end

  RELAXED_UNKNOWN_SLOTS_MAX = 6
  VALIDATION_MODE = ->(params) { (params[:validation_mode].presence || "strict").to_s.downcase }
  CIRCUIT_KEY = "gemini:circuit_open"
  CIRCUIT_TTL = 2.minutes

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

  # ===== AI 生成 → プレビュー =====
  def generate_ai
    tp_params          = params.dig(:travel_plan) || {}
    destination_ids    = Array(tp_params[:destination_ids]).compact_blank
    destinations_names = Destination.where(id: destination_ids).pluck(:name).join(', ')
    start_date         = tp_params[:start_date]
    end_date           = tp_params[:end_date]
    budget             = tp_params[:budget]
    notes              = tp_params[:notes]
    purpose_name = TravelPurpose.find_by(id: tp_params[:travel_purpose_id])&.name
    validation_mode    = VALIDATION_MODE.call(params)

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
      # サーキットが開いていたらAI呼び出しをスキップ
      if Rails.cache.read(CIRCUIT_KEY)
        raise RateLimitExceeded, "circuit_open"
      end

      @ai_plans = call_gemini_api(prompt_text)
      @ai_plans = normalize_ai_plans(@ai_plans)

      # 1st 検証
      issues = collect_meal_issues(@ai_plans, mode: validation_mode)
      Rails.logger.info("[AI VALIDATION 1st] #{issues.inspect}")

      if issues.any?
        @ai_plans.each { |p| attempt_repair_closed_restaurants!(p, max_attempts: 3) }
        issues = collect_meal_issues(@ai_plans, mode: validation_mode)
        Rails.logger.info("[AI VALIDATION after repair] #{issues.inspect}")
      end

      # 最終選別
      @ai_plans = @ai_plans.select { |p| plan_valid?(p, mode: validation_mode) }

      # ======= フォールバック（AI枠が空 or 検証NG） =======
      if @ai_plans.blank?
        @ai_plans = build_plans_via_scrape(
          destinations_names: destinations_names,
          start_date: start_date, end_date: end_date, num_days: num_days
        )
        issues = collect_meal_issues(@ai_plans, mode: validation_mode)
        Rails.logger.info("[SCRAPE VALIDATION] #{issues.inspect}")
        @ai_plans = @ai_plans.select { |p| plan_valid?(p, mode: validation_mode) }
      end

      if @ai_plans.blank?
        raise "AI候補の全プランが無効（閉店/無効URL/判別不能/取得失敗など）でした。"
      end

      Rails.cache.write("ai_plans_for_user_#{current_user.id}", @ai_plans, expires_in: 1.hour)
      respond_to { |format| format.js { render 'generate_ai' } }
    rescue RateLimitExceeded => e
      Rails.cache.write(CIRCUIT_KEY, true, expires_in: CIRCUIT_TTL)
      Rails.logger.warn("Gemini rate limit: #{e.message}")

      # 直接スクレイプでフォールバック
      @ai_plans = build_plans_via_scrape(
        destinations_names: destinations_names,
        start_date: start_date, end_date: end_date, num_days: num_days
      )
      if @ai_plans.present?
        Rails.cache.write("ai_plans_for_user_#{current_user.id}", @ai_plans, expires_in: 1.hour)
        respond_to { |format| format.js { render 'generate_ai' } }
      else
        render js: "alert('AIの利用上限に達しています。代替案の取得にも失敗しました。時間をおいて再試行してください。');"
      end
    rescue => e
      Rails.logger.error("AI生成エラー: #{e.message}")
      render js: "alert('プランの生成に失敗しました（ネットワーク/上限/解析失敗）。モードをRELAXEDにするか、行き先を変えて再実行してください。');"
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

  # ===== 編集保存 =====
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

        plan_stub = { "plan_name" => @travel_plan.name, "itinerary" => new_itinerary }
        issues = collect_meal_issues([plan_stub], mode: 'strict')
        Rails.logger.info("[UPDATE VALIDATION] #{issues.inspect}")

        if issues.any?
          attempt_repair_closed_restaurants!(plan_stub, max_attempts: 3)
          issues = collect_meal_issues([plan_stub], mode: 'strict')
          Rails.logger.info("[UPDATE VALIDATION after repair] #{issues.inspect}")
        end

        if issues.any?
          flash.now[:alert] = "レストランURLの検証に失敗しました（無効URL/閉店UI検出/判別不能過多）。"
          @itinerary_preview = plan_stub["itinerary"]
          hydrate_collections_for_edit and return render(:edit, status: :unprocessable_entity)
        end

        adjust_day1_breakfast_by_distance!(plan_stub)
        @travel_plan.itinerary = plan_stub["itinerary"]
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

  private

  def resolve_layout
    action_name == "show" ? "travel_plans_show" : "application"
  end

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

  # ===== 旅程正規化（Nokogiri版） =====
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
        end

        adjust_day1_breakfast_by_distance!(plan)
      end

      plan
    end
  end

  # ===== 三値検証 =====
  def collect_meal_issues(plans, mode: "strict")
    issues = []
    Array(plans).each_with_index do |plan, pi|
      Array(plan["itinerary"]).each_with_index do |day, di|
        %w[lunch dinner].each do |meal|
          name = day["#{meal}_restaurant"].to_s.strip
          url  = day["#{meal}_restaurant_url"].to_s.strip
          u    = (URI.parse(url) rescue nil)

          state =
            if name.blank? || url.blank?
              :closed
            elsif !(u && u.host&.end_with?("tabelog.com") && TabelogChecker.store_url?(url))
              :closed
            else
              TabelogChecker.status_ex(u)
            end

          issues << { plan_idx: pi, day_idx: di, meal:, name:, url:, state: state } if state != :open
        end
      end
    end
    issues
  end

  def plan_valid?(plan, mode: "strict")
    unknown_count = 0

    all_days_ok = Array(plan["itinerary"]).all? do |day|
      lunch_state  = slot_state(day, "lunch")
      dinner_state = slot_state(day, "dinner")

      if mode == "relaxed"
        day_ok =
          (lunch_state == :open && %i[open unknown].include?(dinner_state)) ||
          (dinner_state == :open && %i[open unknown].include?(lunch_state))

        unknown_count += 1 if lunch_state  == :unknown
        unknown_count += 1 if dinner_state == :unknown
        day_ok
      else
        (lunch_state == :open) && (dinner_state == :open)
      end
    end

    all_days_ok && (mode != "relaxed" || unknown_count <= RELAXED_UNKNOWN_SLOTS_MAX)
  end

  def slot_state(day, meal)
    name = day["#{meal}_restaurant"].to_s.strip
    url  = day["#{meal}_restaurant_url"].to_s.strip
    u    = (URI.parse(url) rescue nil)

    return :closed if name.blank? || url.blank?
    return :closed unless u && u.host&.end_with?("tabelog.com") && TabelogChecker.store_url?(url)

    TabelogChecker.status_ex(u)
  end

  # ===== 自動リペア（AIが使える時のみ呼ばれる前提） =====
  def attempt_repair_closed_restaurants!(plan, max_attempts: 3)
    # 省略：直前までの実装をそのまま（AiRestaurantRepair を呼ぶ）
    # ※429時は generate_ai 側で rescue し、ここに来ない設計
    it = Array(plan["itinerary"])
    return if it.blank?

    attempts = 0
    loop do
      break if attempts >= max_attempts
      attempts += 1

      changed = false

      it.each do |day|
        %w[lunch dinner].each do |meal|
          name_key = "#{meal}_restaurant"
          url_key  = "#{meal}_restaurant_url"

          name = day[name_key].to_s.strip
          url  = day[url_key].to_s.strip
          u    = (URI.parse(url) rescue nil)

          state =
            if name.blank? || url.blank?
              :closed
            elsif !(u && u.host&.end_with?("tabelog.com") && TabelogChecker.store_url?(url))
              :closed
            else
              TabelogChecker.status_ex(u)
            end

          next if state == :open
          replacement = AiRestaurantRepair.replace_one(
            place_text: day["place"].to_s, meal: meal, avoid_names: [name].compact_blank
          )
          rep_name = replacement["name"].to_s.strip
          rep_url  = replacement["url"].to_s.strip
          next if rep_name.blank? || rep_url.blank?
          next unless TabelogChecker.store_url?(rep_url)
          uu = (URI.parse(rep_url) rescue nil)
          next unless uu && uu.host&.end_with?("tabelog.com")
          rep_state = TabelogChecker.status_ex(uu)
          next unless rep_state == :open || rep_state == :unknown
          day[name_key] = rep_name
          day[url_key]  = rep_url
          changed = true
        end
      end

      break unless changed
    end
  end

  # ===== URLサニタイズ =====
  def sanitize_tabelog_pair(name, url)
    url  = url.to_s.strip
    name = name.to_s.strip
    return { name: "", url: "" } if name.blank?

    uri = (URI.parse(url) rescue nil)
    return { name: name, url: "" } unless uri&.host&.end_with?("tabelog.com")
    return { name: name, url: "" } unless TabelogChecker.store_url?(url)

    title = TabelogChecker.fetch_title(uri)
    store = extract_tabelog_store_name(title)
    { name: (store.presence || name), url: uri.to_s }
  rescue
    { name: name, url: "" }
  end

  def sanitize_any_pair(name, url)
    url  = url.to_s.strip
    name = name.to_s.strip
    return { name: name, url: "" } if url.blank?

    uri = (URI.parse(url) rescue nil)
    return { name: name, url: "" } unless uri && %w(http https).include?(uri.scheme)

    { name: name, url: url }
  rescue
    { name: name, url: "" }
  end

  def extract_tabelog_store_name(title)
    return "" if title.blank?
    return title.split(" - 食べログ").first.strip if title.include?(" - 食べログ")
    return title.split("｜食べログ").first.strip  if title.include?("｜食べログ")
    title.sub(/食べログ\s*$/, '').strip
  end

  # ===== Day1 朝食の自動調整 =====
  def adjust_day1_breakfast_by_distance!(plan)
    it = Array(plan["itinerary"])
    return if it.blank?

    day1 = it.find { |d| d["day"].to_i == 1 } || it.first
    return unless day1

    home_pref = current_user&.home_destination&.prefecture_group&.name.to_s
    dest_pref = PrefectureDistance.extract_pref_from_text(day1["place"].to_s)
    return if home_pref.blank? || dest_pref.blank?

    km = PrefectureDistance.distance_km_between(home_pref, dest_pref)
    return if km.nil?

    if km >= PrefectureDistance::BREAKFAST_DISTANCE_KM
      day1["breakfast_restaurant"]     = "出発地で朝食（#{home_pref}）"
      day1["breakfast_restaurant_url"] = ""
    else
      day1["breakfast_restaurant"]     = "現地のカフェで朝食（#{dest_pref}）"
      day1["breakfast_restaurant_url"] = ""
    end
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
      contents: [ { role: "user", parts: [ { text: prompt_text } ] } ],
      generationConfig: { response_mime_type: "application/json", temperature: 0.12, topP: 0.4, topK: 30 }
    }

    response = conn.post do |req|
      req.url "?key=#{ENV['GEMINI_API_KEY']}"
      req.headers['Content-Type'] = 'application/json'
      req.body = body.to_json
    end

    Rails.logger.debug("Gemini raw response: #{response.body.inspect}")

    if response.body.is_a?(Hash) && response.body["error"]
      err = response.body["error"]
      if err["code"].to_i == 429 || err["status"].to_s == "RESOURCE_EXHAUSTED"
        raise RateLimitExceeded, err["message"].to_s
      end
      Rails.logger.warn("Gemini error: #{err.inspect}")
      return []
    end

    json_text = response.body.dig("candidates", 0, "content", "parts", 0, "text")
    parse_ai_json(json_text)
  rescue RateLimitExceeded
    raise
  rescue => e
    Rails.logger.error("Gemini API呼び出しエラー: #{e.message}")
    []
  end

  def parse_ai_json(json_text)
    return [] if json_text.blank?
    text = json_text.to_s.strip
    if (m = text.match(/```json\s*([\s\S]*?)```/i)); text = m[1].to_s.strip; end
    if text.include?('[') && text.include?(']')
      start  = text.index('['); finish = text.rindex(']'); candidate = text[start..finish] rescue nil
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
              "place": "行き先の地名（例：東京都新宿区 等）",
              "breakfast_restaurant": "朝食の店名（例: 出発地で朝食／現地のカフェ）",
              "breakfast_restaurant_url": "朝食のURL（空文字可）",
              "morning_activity": "午前の活動内容",
              "lunch_restaurant": "昼食の店名",
              "lunch_restaurant_url": "https://tabelog.com/xxxxx/....../12345678/",
              "afternoon_activity": "午後の活動内容",
              "dinner_restaurant": "夕食の店名",
              "dinner_restaurant_url": "https://tabelog.com/xxxxx/....../12345678/",
              "stay_hotel": "宿泊ホテルの具体的な名前",
              "stay_hotel_url": "宿泊ホテルの予約URL（例:公式HP）"
            }
          ]
        }
      ]

      **厳守事項（重要）**
      - 昼食/夕食のURLは tabelog.com の**店舗詳細ページ**直リンク（数字IDで終わるURL）。
      - 閉店UIのあるページは禁止（レビュー本文の“閉店”は無視）。
      - 店名とURLは同一店舗に一致させること。
      - 朝食URLは空文字可。

      **ユーザーの旅行情報:**
      - 旅行目的: #{purpose_name.presence || "（未指定）"}
      - 行き先: #{destinations_names.presence || "（未指定）"}
      - 期間: #{start_date.presence || "未定"} 〜 #{end_date.presence || "未定"}（#{num_days}日間）
      - 総予算: #{budget.presence || "未設定"} 円
      - その他ニーズ: #{notes.presence || "特になし"}

      **出力規約（再掲）**
      - 回答は **JSON配列のみ** をそのまま出力。コードブロックや注記は一切不要。
    PROMPT
  end

  # ====== フォールバック（AI非依存）：食べログをスクレイプして店舗を差し込む ======
  def build_plans_via_scrape(destinations_names:, start_date:, end_date:, num_days:)
    city = destinations_names.to_s.split(/[,、]/).first.to_s.presence || "東京都"
    days = (0...num_days).map { |i| (Date.parse(start_date) + i).strftime("%Y-%m-%d") rescue "" }

    # 候補店舗を確保（多めに取得）
    candidates = TabelogSearch.top_stores(area_text: city, limit: 12)

    # open/unknown だけに絞る
    usable = candidates.select do |h|
      url = h[:url]; next false if url.blank?
      u = URI.parse(url) rescue nil; next false unless u
      st = TabelogChecker.status_ex(u)
      st == :open || st == :unknown
    end

    # 昼夜用に交互に割り当て
    lunch_list  = usable.each_slice(2).map(&:first).compact
    dinner_list = usable.each_slice(2).map { |a| a[1] }.compact

    # 2案作る
    plans = 2.times.map do |pi|
      it = []
      days.each_with_index do |d, idx|
        lunch  = lunch_list[(idx + pi) % lunch_list.size]  rescue nil
        dinner = dinner_list[(idx + pi) % dinner_list.size] rescue nil

        # 最低限チェック
        if lunch.nil? || dinner.nil?
          # 足りない場合は usable からリサイクル
          lunch  ||= usable[(idx*2 + pi) % usable.size] rescue nil
          dinner ||= usable[(idx*2 + pi + 1) % usable.size] rescue nil
        end

        it << {
          "day" => idx + 1,
          "date" => d,
          "place" => city,
          "breakfast_restaurant" => (idx.zero? ? "出発地で朝食" : "ホテル朝食"),
          "breakfast_restaurant_url" => "",
          "morning_activity" => idx.zero? ? "移動／現地到着後に周辺散策" : "観光スポット巡り",
          "lunch_restaurant" => lunch&.dig(:name).to_s,
          "lunch_restaurant_url" => lunch&.dig(:url).to_s,
          "afternoon_activity" => idx.zero? ? "主要スポット観光" : "ショッピング／公園で休憩",
          "dinner_restaurant" => dinner&.dig(:name).to_s,
          "dinner_restaurant_url" => dinner&.dig(:url).to_s,
          "stay_hotel" => idx == days.size - 1 ? "出発地へ移動" : "#{city}内ホテル",
          "stay_hotel_url" => ""
        }
      end

      {
        "plan_name" => "#{city} #{num_days}日間ベースプラン#{pi + 1}（フォールバック）",
        "itinerary" => it
      }
    end

    # 正規化して返す（URLサニタイズ等）
    normalize_ai_plans(plans)
  rescue => e
    Rails.logger.error("build_plans_via_scrape error: #{e.class}: #{e.message}")
    []
  end
end
