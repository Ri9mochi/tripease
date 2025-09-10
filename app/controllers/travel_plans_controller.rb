# app/controllers/travel_plans_controller.rb
require 'faraday'
require 'json'
require 'net/http'
require 'uri'

class TravelPlansController < ApplicationController
  # before_action :authenticate_user!

  # ==== 食べログ 閉店・無効判定 ====
  TABELOG_CLOSED_PATTERNS = [
    /閉店/i, /閉業/i, /休業/i, /掲載保留/i,
    /このページは表示できません/i, /not\s+available/i
  ].freeze

  TABELOG_CLOSED_URL_PATTERNS = [
    %r{/rst_closed/}i, %r{/closed}i
  ].freeze

  # “店舗ページ”URLの形（シェイプ）判定用
  TABELOG_STORE_PATH = %r{\A/[a-z]+/A\d{4}/A\d{6}/\d+/?\z}i

  # 403/タイムアウトなどオンライン検証が難しい場合に
  # 形（シェイプ）がOKなら合格とみなす軽量モード（推奨: 本番=1）
  LIGHT_TABELOG_VALIDATION = ENV.fetch("LIGHT_TABELOG_VALIDATION", "1") == "1"

  HTTP_UA = "Mozilla/5.0 (TravelEaseBot; +https://example.com)".freeze

  # 都道府県 -> tabelog スラッグ（主要のみ記載、必要に応じて拡張）
  PREF_SLUGS = {
    "北海道"=>"hokkaido","青森"=>"aomori","岩手"=>"iwate","宮城"=>"miyagi","秋田"=>"akita","山形"=>"yamagata","福島"=>"fukushima",
    "茨城"=>"ibaraki","栃木"=>"tochigi","群馬"=>"gunma","埼玉"=>"saitama","千葉"=>"chiba","東京"=>"tokyo","神奈川"=>"kanagawa",
    "新潟"=>"niigata","富山"=>"toyama","石川"=>"ishikawa","福井"=>"fukui","山梨"=>"yamanashi","長野"=>"nagano",
    "岐阜"=>"gifu","静岡"=>"shizuoka","愛知"=>"aichi","三重"=>"mie",
    "滋賀"=>"shiga","京都"=>"kyoto","大阪"=>"osaka","兵庫"=>"hyogo","奈良"=>"nara","和歌山"=>"wakayama",
    "鳥取"=>"tottori","島根"=>"shimane","岡山"=>"okayama","広島"=>"hiroshima","山口"=>"yamaguchi",
    "徳島"=>"tokushima","香川"=>"kagawa","愛媛"=>"ehime","高知"=>"kochi",
    "福岡"=>"fukuoka","佐賀"=>"saga","長崎"=>"nagasaki","熊本"=>"kumamoto","大分"=>"oita","宮崎"=>"miyazaki","鹿児島"=>"kagoshima",
    "沖縄"=>"okinawa"
  }.freeze

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

  # ===== AI 生成 =====
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
      # 1) 生成
      plans = call_gemini_api(prompt_text)

      # 2) 正規化（URL整合・朝食補完・最終宿泊制御）
      plans = normalize_ai_plans(plans, notes: notes)

      # 3) 必須項目の穴埋め（初日含め place/morning/afternoon 空禁止）
      plans = enforce_completeness!(plans, destinations_names)

      # 4) 食べログURL必須検証 → 不備箇所だけ複数候補の再生成を依頼（最大4回）
      issues = collect_meal_issues(plans)
      attempts = 0
      while issues.any? && attempts < 4
        attempts += 1
        repair_prompt = build_meal_repair_prompt(plans, issues, {
          destinations: destinations_names,
          dates: { start: start_date, end: end_date },
          purpose: purpose_name,
          notes: notes
        })
        corrections = call_gemini_api(repair_prompt)
        plans = apply_meal_corrections(plans, corrections) # ← 候補から“通るものだけ”採用
        plans = normalize_ai_plans(plans, notes: notes)
        plans = enforce_completeness!(plans, destinations_names)
        issues = collect_meal_issues(plans)
      end

      if issues.any?
        Rails.logger.warn("Tabelog validation failed after repair: #{issues.inspect}")
        render js: "alert('レストラン情報の検証に失敗しました。条件（エリア/日程/人数/ジャンル）を少し変えて再生成してください。');" and return
      end

      @ai_plans = plans
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

  # ===== Strong Params =====
  def travel_plan_params
    params.require(:travel_plan).permit(
      :name, :start_date, :end_date, :budget, :notes, :status,
      :travel_purpose_id,
      destination_ids: []
    )
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

  # ===== 正規化処理 =====
  # - レストランURL：形が不正/閉店と推定 → 空に（後段で修復を必須化）
  # - 朝食の補完
  # - 最終日の宿泊はnotesに明示が無ければ空欄
  def normalize_ai_plans(plans, notes:)
    return [] unless plans.is_a?(Array)

    plans.map do |plan|
      plan = plan.deep_dup
      it = plan["itinerary"]

      if it.is_a?(Array)
        it.each_with_index do |day, idx|
          pref = prefecture_slug_from(day["place"])

          # 昼/夜
          %w[lunch dinner].each do |meal|
            name_key = "#{meal}_restaurant"
            url_key  = "#{meal}_restaurant_url"
            fixed    = sanitize_tabelog_pair(day[name_key], day[url_key], prefecture_slug: pref)
            day[name_key] = fixed[:name]
            day[url_key]  = fixed[:url]
          end

          # 朝食（URLは任意）
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

          # 最終日の宿泊は原則空欄（notesに明示があれば残す）
          if idx == it.length - 1
            wants_lodging = notes.to_s.match?(/宿泊|ホテル|滞在|連泊|最終日も泊/i)
            unless wants_lodging
              day["stay_hotel"]     = ""
              day["stay_hotel_url"] = ""
            end
          end
        end
      end

      plan
    end
  end

  # ===== “空を許さない” 必須項目の強制埋め（初日含む） =====
  def enforce_completeness!(plans, destinations_names)
    default_place = destinations_names.to_s.split(',').first.to_s.strip
    default_place = "観光地" if default_place.blank?
    activity_fallback = "観光・散策"

    plans.each do |plan|
      it = Array(plan["itinerary"])
      it.each_with_index do |day, idx|
        day["place"]               = (day["place"].presence || (idx.positive? ? it[idx - 1]["place"] : default_place) || default_place)
        day["morning_activity"]    = (day["morning_activity"].presence || activity_fallback)
        day["afternoon_activity"]  = (day["afternoon_activity"].presence || activity_fallback)
      end
    end
    plans
  end

  # ===== 食べログURL 必須検証 =====
  def collect_meal_issues(plans)
    issues = []
    plans.each_with_index do |plan, pi|
      Array(plan["itinerary"]).each_with_index do |day, di|
        pref = prefecture_slug_from(day["place"])
        %w[lunch dinner].each do |meal|
          url = day["#{meal}_restaurant_url"].to_s.strip
          valid = url.present? && tabelog_store_ok?(url, prefecture_slug: pref)
          issues << { plan_idx: pi, day_idx: di, meal: meal, reason: (url.blank? ? "missing_url" : "invalid_or_closed") } unless valid
        end
      end
    end
    issues
  end

  # ===== 修正プロンプト（複数候補を返させる） =====
  def build_meal_repair_prompt(plans, issues, context)
    targets = issues.map do |i|
      day = plans[i[:plan_idx]]["itinerary"][i[:day_idx]]
      {
        plan_index: i[:plan_idx],
        day:        day["day"],
        date:       day["date"],
        area:       day["place"],
        meal:       i[:meal],
        prefecture_slug: prefecture_slug_from(day["place"]) # 例: "gunma"
      }
    end

    <<~PROMPT
      あなたは旅行プランの修正アシスタントです。
      入力された各「修正対象」について、**実在し現在営業中**のレストラン候補を**最大5件**返してください。
      各候補は **tabelog.com の“店舗ページ”URL** と **店名**のペアで、**同一店舗に一致**していること。

      返答は**JSON配列のみ**。スキーマ:
      [
        {
          "plan_index": <数値>,
          "day": <数値>,
          "meal": "lunch" | "dinner",
          "candidates": [
            { "name": "<店舗名>", "url": "https://tabelog.com/...." },
            ...
          ]
        }
      ]

      厳守事項:
      - URLは tabelog.com の**店舗ページ**のみ（検索/特集/ランキングURLは禁止）
      - 200で到達可能
      - 閉店/休業/掲載保留の店舗は返さない
      - "prefecture_slug" が与えられている場合、**URLは必ず https://tabelog.com/{prefecture_slug}/ で始まること**

      参考情報:
      #{context.to_json}

      修正対象:
      #{targets.to_json}
    PROMPT
  end

  # ===== 候補から“通るもの”だけを採用（旧フォーマットにも後方互換） =====
  def apply_meal_corrections(plans, corrections)
    return plans unless corrections.is_a?(Array)

    corrections.each do |entry|
      next unless entry.is_a?(Hash)

      plan_index = entry["plan_index"]
      day_num    = entry["day"]
      meal       = entry["meal"]

      candidates =
        if entry["candidates"].is_a?(Array)
          entry["candidates"]
        elsif entry["name"].present? && entry["url"].present?
          [ { "name" => entry["name"], "url" => entry["url"] } ]
        else
          []
        end

      next if candidates.empty?
      plan = plans[plan_index]
      next unless plan

      day = Array(plan["itinerary"]).find { |d| d["day"] == day_num }
      next unless day

      pref = prefecture_slug_from(day["place"])
      chosen = nil
      candidates.each do |cand|
        url  = cand["url"].to_s.strip
        name = cand["name"].to_s.strip
        if url.present? && tabelog_store_ok?(url, prefecture_slug: pref)
          chosen = { name: name, url: url }
          break
        end
      end

      if chosen
        day["#{meal}_restaurant"]     = chosen[:name]
        day["#{meal}_restaurant_url"] = chosen[:url]
      end
    end

    plans
  end

  # ===== URL/ページ検証（形→オンライン） =====
  # prefecture_slug が与えられた場合は /{slug}/ で始まることも要件に含める
  def tabelog_store_ok?(url, prefecture_slug: nil)
    uri = safe_parse_uri(url)
    return false unless tabelog_store_shape_ok?(uri, prefecture_slug: prefecture_slug)

    # 軽量モード：形がOKなら合格（WAF対策）
    return true if LIGHT_TABELOG_VALIDATION

    # 厳密モード：オンライン検証（取れなければ形OKでソフト合格）
    final_uri, resp = follow_redirects(uri, limit: 3)
    unless resp && resp.status.to_i == 200
      Rails.logger.info("tabelog soft-pass (#{resp&.status}): #{url}")
      return true
    end

    return false if TABELOG_CLOSED_URL_PATTERNS.any? { |re| final_uri.to_s.match?(re) }

    body  = resp.body.to_s
    title = body[/\<title\>(.*?)\<\/title\>/im, 1].to_s.strip
    return false if TABELOG_CLOSED_PATTERNS.any? { |re| title.match?(re) || body.match?(re) }

    (title.include?("食べログ") || title.include?("Tabelog"))
  rescue
    false
  end

  # 形（シェイプ）だけで“店舗ページ”かを判定
  def tabelog_store_shape_ok?(uri, prefecture_slug: nil)
    return false unless uri&.scheme&.in?(%w[http https])
    return false unless uri.host&.end_with?("tabelog.com")
    return false unless uri.path&.match?(TABELOG_STORE_PATH)
    return false if TABELOG_CLOSED_URL_PATTERNS.any? { |re| uri.to_s.match?(re) }
    if prefecture_slug.present?
      return false unless uri.path.start_with?("/#{prefecture_slug}/")
    end
    true
  end

  # 食べログURLの正規化（形が不正/閉店の疑いは空へ、形OKなら保持）
  def sanitize_tabelog_pair(name, url, prefecture_slug: nil)
    url  = url.to_s.strip
    name = name.to_s.strip
    return { name: "", url: "" } if url.blank?

    uri = safe_parse_uri(url)
    return { name: "", url: "" } unless tabelog_store_shape_ok?(uri, prefecture_slug: prefecture_slug)

    # 軽量モードはそのまま保持（店名はもらったまま）
    return { name: name, url: url } if LIGHT_TABELOG_VALIDATION

    # 厳密モード：可能ならタイトルから店名補正
    final_uri, resp = follow_redirects(uri, limit: 3)
    if resp && resp.status.to_i == 200
      body  = resp.body.to_s
      title = body[/\<title\>(.*?)\<\/title\>/im, 1].to_s.strip
      if TABELOG_CLOSED_PATTERNS.any? { |re| title.match?(re) || body.match?(re) }
        return { name: "", url: "" }
      end
      store = extract_tabelog_store_name(title)
      { name: (store.presence || name), url: final_uri.to_s }
    else
      Rails.logger.info("tabelog sanitize soft-pass (#{resp&.status}): #{url}")
      { name: name, url: url }
    end
  rescue
    { name: "", url: "" }
  end

  # 任意URL（200以外は落とす）
  def sanitize_any_pair(name, url)
    url  = url.to_s.strip
    name = name.to_s.strip
    return { name: name, url: "" } if url.blank?

    uri = safe_parse_uri(url)
    return { name: name, url: "" } unless uri && %w(http https).include?(uri.scheme)

    final_uri, resp = follow_redirects(uri, limit: 2)
    return { name: name, url: "" } unless resp && resp.status.to_i == 200

    { name: name, url: final_uri.to_s }
  rescue
    { name: name, url: "" }
  end

  def safe_parse_uri(url)
    URI.parse(url)
  rescue
    nil
  end

  # 3xx を最大 limit 回追従
  def follow_redirects(uri, limit: 3)
    current_uri = uri
    resp = nil

    limit.times do
      conn = Faraday.new(url: "#{current_uri.scheme}://#{current_uri.host}") do |f|
        f.headers["User-Agent"]      = HTTP_UA
        f.headers["Accept-Language"] = "ja-JP,ja;q=0.9"
        f.headers["Accept"]          = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        f.options.timeout            = 5
        f.options.open_timeout       = 4
      end
      path = current_uri.request_uri.presence || "/"
      resp = (conn.get(path) rescue nil)
      break unless resp

      code = resp.status.to_i
      if code.between?(300, 399)
        loc = resp.headers["location"]
        break unless loc
        begin
          next_uri = URI.parse(loc)
          unless next_uri.host
            next_uri = URI.join("#{uri.scheme}://#{uri.host}", loc)
          end
          current_uri = next_uri
          next
        rescue
          break
        end
      else
        break
      end
    end

    [current_uri, resp]
  rescue
    [uri, nil]
  end

  def extract_tabelog_store_name(title)
    return "" if title.blank?
    return title.split(" - 食べログ").first.strip if title.include?(" - 食べログ")
    return title.split("｜食べログ").first.strip  if title.include?("｜食べログ")
    title.sub(/食べログ\s*$/, '').strip
  end

  # ===== 補助: place から都道府県スラッグを推定 =====
  def prefecture_slug_from(place_text)
    t = place_text.to_s
    PREF_SLUGS.each do |jp, slug|
      return slug if t.include?(jp)
    end
    nil
  end

  # ===== 生成プロンプト =====
  def generate_prompt(destinations_names, start_date, end_date, budget, notes, num_days, purpose_name)
    <<~PROMPT
      あなたは旅行プランを提案するAIアシスタントです。
      ユーザーの旅行ニーズに基づいて、#{num_days}日間の旅行プランを2案提案してください。

      **出力形式の厳守:**
      回答は以下のJSON配列「のみ」を出力してください（前後の文章・注釈・コードブロックは禁止）。
      [
        {
          "plan_name": "プランタイトル",
          "itinerary": [
            {
              "day": 1,
              "date": "YYYY-MM-DD",
              "place": "地名（空文字禁止）",
              "breakfast_restaurant": "朝食の店名（例: ホテル朝食）",
              "breakfast_restaurant_url": "URL（空文字可）",
              "morning_activity": "午前の活動内容（空文字禁止）",
              "lunch_restaurant": "昼食の店名（空文字禁止）",
              "lunch_restaurant_url": "tabelog.com の“店舗ページ”URL（必須）",
              "afternoon_activity": "午後の活動内容（空文字禁止）",
              "dinner_restaurant": "夕食の店名（空文字禁止）",
              "dinner_restaurant_url": "tabelog.com の“店舗ページ”URL（必須）",
              "stay_hotel": "宿泊ホテル名（最終日は原則空文字）",
              "stay_hotel_url": "ホテル公式URL（空文字可）"
            }
          ]
        }
      ]

      **制約（厳守）:**
      - レストランは「現在営業中」の実在店舗のみ。閉店/休業/掲載保留は**絶対に含めない**。
      - レストランURLは tabelog.com の**店舗ページ**のみ（検索/特集/ランキングURLは禁止）。
      - 店名とURLは**同一店舗**に一致（支店違いURL不可）。
      - URLは必ず200で到達可能。
      - 各日 place / morning_activity / afternoon_activity は空文字禁止。
      - **最終日の宿泊先は、ユーザーの「その他ニーズ」に宿泊/ホテル等の明示がなければ空欄にする。**

      ユーザーの旅行情報:
      - 目的: #{purpose_name.presence || "（未指定）"}
      - 行き先: #{destinations_names.presence || "（未指定）"}
      - 期間: #{start_date.presence || "未定"} 〜 #{end_date.presence || "未定"}（#{num_days}日間）
      - 予算: #{budget.presence || "未設定"}
      - その他ニーズ: #{notes.presence || "特になし"}
    PROMPT
  end
end
