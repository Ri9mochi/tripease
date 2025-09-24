# app/services/ai_restaurant_repair.rb
class AiRestaurantRepair
  class << self
    def replace_one(place_text:, meal:, avoid_names: [])
      prompt = build_prompt(place_text: place_text, meal: meal, avoid_names: avoid_names)
      res = call_gemini(prompt)
      parse_json_obj(res)
    rescue
      {}
    end

    private

    def build_prompt(place_text:, meal:, avoid_names:)
      <<~P
        あなたは旅行レストラン選定のアシスタントです。
        指定の都市・エリアにある「営業中の」実在店舗を1件だけ提案してください。
        出力は次のJSON「だけ」にしてください（前後の文や注釈は禁止）:
        {"name":"店舗名","url":"https://tabelog.com/...."}

        厳守条件:
        - URLは tabelog.com の「店舗詳細ページ」への直リンク。
          例: https://tabelog.com/tokyo/A1304/A130401/13001468/
          NG例: トップページ/エリアページ/検索一覧/まとめ記事/写真ページ
        - HTTP 2xx で到達可能なページ。
        - ページに「閉店」「閉業」「営業終了」「閉鎖」「休業中」「この店舗は掲載保留」等の語が含まれない。
        - 以下の店舗名は避ける: #{avoid_names.compact_blank.join(", ").presence || "(指定なし)"}

        入力:
        - 都市・エリア: #{place_text}
        - 区分: #{meal}（lunch/dinner のいずれか）
      P
    end

    def call_gemini(prompt_text)
      url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
      conn = Faraday.new(url: url) { |f| f.request :json; f.response :json }
      body = {
        contents: [ { role: "user", parts: [ { text: prompt_text } ] } ],
        generationConfig: {
          response_mime_type: "application/json",
          temperature: 0.15,
          topP: 0.3,
          topK: 20
        }
      }
      response = conn.post do |req|
        req.url "?key=#{ENV['GEMINI_API_KEY']}"
        req.headers['Content-Type'] = 'application/json'
        req.body = body.to_json
      end
      response.body.dig("candidates", 0, "content", "parts", 0, "text").to_s
    rescue => e
      Rails.logger.error("Gemini repair呼び出しエラー: #{e.message}")
      ""
    end

    def parse_json_obj(text)
      t = text.to_s.strip
      if (m = t.match(/```json\s*([\s\S]*?)```/i))
        t = m[1].to_s.strip
      end
      JSON.parse(t)
    rescue
      {}
    end
  end
end
