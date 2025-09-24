# app/services/tabelog_search.rb
require 'faraday'
require 'faraday/follow_redirects'
require 'faraday/retry'
require 'nokogiri'
require 'uri'

# **AIが使えない時のフォールバック**として、
# エリア名から食べログの「店舗詳細URL」を複数件スクレイピングで取得する。
# - 返すのは {name:, url:} の配列（最大 limit 件）
# - Nokogiri で一覧→店舗詳細リンク(/.../\d{8}/)を抽出
# - 取得後に TabelogChecker.store_url? で形を確認
class TabelogSearch
  class << self
    # area_text 例: "東京都新宿区", "京都府京都市", "大阪府大阪市"
    def top_stores(area_text:, limit: 8)
      return [] if area_text.to_s.strip.empty?
      q = URI.encode_www_form_component(area_text.to_s.strip)
      # 並び順: 評価順 or 人気順（SrtT=rt は人気/評価系。状況で変更可）
      url = "https://tabelog.com/rstLst/?SrtT=rt&sa=#{q}"

      res = http_get(url)
      return [] unless res && (200..299).include?(res.status.to_i)

      doc = Nokogiri::HTML.parse(res.body.to_s)
      links = []

      # 新旧UI両対応でリンクを拾う（候補を広めに）
      selectors = [
        'a.cpy-rst-name',                    # 旧UI 店名
        '.list-rst__rst-name a',            # 旧UI リスト
        '.rstlist-info .list-rst__name a',  # バリエーション
        'a.js-rst-name',                     # 予備
        '.rstdtl-top a'                      # 予備
      ]

      selectors.each do |sel|
        doc.css(sel).each do |a|
          href = a['href'].to_s
          next unless href.match?(%r{/(\d{8})/})
          next unless href.include?('tabelog.com')
          name = a.text.to_s.strip
          links << { name:, url: href }
        end
        break if links.size >= limit * 2 # 多少多めに取って後でふるい
      end

      # 重複排除、店舗詳細URLのみに絞る
      uniq = links.uniq { |h| h[:url] }.select { |h| TabelogChecker.store_url?(h[:url]) }

      # 先頭から limit 件
      uniq.take(limit)
    rescue => e
      Rails.logger.debug("TabelogSearch.top_stores error: #{e.class}: #{e.message}")
      []
    end

    private

    def http_get(url)
      uri = URI.parse(url)
      Faraday.new(url: "#{uri.scheme}://#{uri.host}") do |f|
        f.request :retry, max: 2, interval: 0.3, interval_randomness: 0.2, backoff_factor: 2,
                 retry_statuses: [408, 409, 420, 429, 500, 502, 503, 504]
        f.response :follow_redirects, limit: 5
        f.options.timeout      = 7
        f.options.open_timeout = 3
        f.headers['User-Agent'] = "Mozilla/5.0 (Tripease Bot; +https://example.com)"
        f.headers['Accept-Language'] = "ja,en;q=0.8"
        f.headers['Referer'] = "https://www.google.com/"
      end.get(uri.request_uri.presence || "/")
    rescue
      nil
    end
  end
end
