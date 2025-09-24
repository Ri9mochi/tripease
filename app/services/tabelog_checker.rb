# app/services/tabelog_checker.rb
# frozen_string_literal: true

require 'uri'
require 'json'
require 'faraday'
require 'faraday/follow_redirects'
require 'faraday/retry'
require 'nokogiri'

# 食べログの店舗詳細ページを取得し、DOM上の「閉店/掲載停止UI」だけを根拠に判定するチェッカー。
# - ホワイトリストは使わない
# - レビュー本文の「閉店」等の文字列には反応しない（誤検知防止）
# 返却: :open / :closed / :unknown
class TabelogChecker
  # https://tabelog.com/xxxxx/....../12345678/ のように「数値IDで終わる」店舗詳細URLを許容
  STORE_URL_REGEX = %r{\Ahttps?://(?:www\.)?tabelog\.com/[^/]+/(?:[^/]+/)*\d+/(?:\?.*)?\z}i

  CACHE_TTL = 24.hours

  class << self
    # @param uri [URI,String]
    # @return [:open, :closed, :unknown]
    def status_ex(uri)
      url = uri.is_a?(URI) ? uri : (URI.parse(uri.to_s) rescue nil)
      return :unknown unless url

      # 開発向けバイパス（ネットワークに出ない）
      if Rails.env.development? && ENV['SKIP_TABELOG_FETCH'] == '1'
        return store_url?(url.to_s) ? :unknown : :unknown
      end

      cache_key = "tabelog:status_ex:v2:#{url}"
      cached = Rails.cache.read(cache_key)
      return cached if %i[open closed unknown].include?(cached)

      res = http_get(url)
      return cache_and(:unknown, cache_key) unless res && (200..299).include?(res.status.to_i)

      html = res.body.to_s

      # 1) 店舗詳細ページらしいか（JSON-LD / UIシグナル）
      kind = page_kind(html)
      return cache_and(:unknown, cache_key) unless kind == :store

      # 2) 明示的な閉店/掲載停止UIの有無
      state = interpret_state_from_dom(html)
      cache_and(state, cache_key)
    rescue => e
      Rails.logger.debug("[TabelogChecker] status_ex error: #{e.class}: #{e.message}")
      :unknown
    end

    # ベストエフォートのタイトル取得（検証/ログ用。閉店判定には使わない）
    # @param uri [URI,String]
    # @return [String]
    def fetch_title(uri)
      url = uri.is_a?(URI) ? uri : (URI.parse(uri.to_s) rescue nil)
      return '' unless url

      key = "tabelog:title:v2:#{url}"
      cached = Rails.cache.read(key)
      return cached if cached

      res = http_get(url)
      return '' unless res && (200..299).include?(res.status.to_i)

      title = Nokogiri::HTML.parse(res.body.to_s).at('title')&.text.to_s.strip
      Rails.cache.write(key, title, expires_in: CACHE_TTL)
      title
    rescue
      ''
    end

    # URLが店舗詳細URLの形か？
    # @param url [String]
    # @return [Boolean]
    def store_url?(url)
      url.to_s.match?(STORE_URL_REGEX)
    end

    private

    # Faraday GET（リトライ＆リダイレクト追従）
    # @param uri [URI]
    # @return [Faraday::Response, nil]
    def http_get(uri)
      Faraday.new(url: "#{uri.scheme}://#{uri.host}") do |f|
        f.request :retry,
                  max: 2,
                  interval: 0.3,
                  interval_randomness: 0.2,
                  backoff_factor: 2,
                  retry_statuses: [408, 409, 420, 429, 500, 502, 503, 504]
        f.response :follow_redirects, limit: 5
        f.options.timeout      = 7
        f.options.open_timeout = 3
        f.headers['User-Agent'] = 'Mozilla/5.0 (Tripease Bot; +https://example.com)'
        f.headers['Accept-Language'] = 'ja,en;q=0.8'
        f.headers['Referer'] = 'https://www.google.com/'
      end.get(uri.request_uri.presence || '/')
    rescue => e
      Rails.logger.debug("[TabelogChecker] http_get error: #{e.class}: #{e.message}")
      nil
    end

    # ページ種別推定：店舗詳細なら :store、その他は :unknown
    # @param html [String]
    # @return [:store, :unknown]
    def page_kind(html)
      doc = Nokogiri::HTML.parse(html)

      # JSON-LD (@type: Restaurant / LocalBusiness / FoodEstablishment)
      types = extract_jsonld_types(doc)
      return :store if (types & %w[Restaurant LocalBusiness FoodEstablishment]).any?

      # UIのシグナル（観測値ベース、将来追加可）
      ui_hits = [
        '.rstinfo-table',       # 旧: 基本情報テーブル
        '#rst-data',            # js用データ領域
        '.rstdtl-top',          # 詳細上部
        '.c-rstInfo',           # 新UI
        '.p-restaurant-header', # 予備
        '.rstinfo',             # 予備
      ].any? { |sel| doc.at_css(sel) }

      ui_hits ? :store : :unknown
    rescue
      :unknown
    end

    # JSON-LDの @type を抽出
    # @param doc [Nokogiri::HTML::Document]
    # @return [Array<String>]
    def extract_jsonld_types(doc)
      types = []
      doc.css('script[type="application/ld+json"]').each do |tag|
        begin
          parsed = JSON.parse(tag.text)
          arr = parsed.is_a?(Array) ? parsed : [parsed]
          arr.each do |obj|
            t = obj['@type']
            types << t if t.is_a?(String)
            types.concat(t) if t.is_a?(Array)
          end
        rescue
          # JSONパース失敗は無視
        end
      end
      types.flatten.compact
    end

    # 明示的な閉店/掲載停止UIだけを見る（本文の語彙は使わない）
    # @param html [String]
    # @return [:open, :closed, :unknown]
    def interpret_state_from_dom(html)
      doc = Nokogiri::HTML.parse(html)

      # 代表的な閉店UIセレクタ群（観測ベース、必要に応じて増やす）
      closed_selectors = %w[
        .rstinfo-closed
        .rstinfo_Closed
        .rstlst-closed
        #rst-closed
        .c-closedNotice
        .c-notFound
        .rstinfo-notfound
        .rstinfo-noentry
      ]
      return :closed if closed_selectors.any? { |sel| doc.at_css(sel) }

      # 掲載保留/停止を closed 相当として扱う
      suspended_selectors = %w[
        .rstinfo-suspended
        .c-suspendedNotice
      ]
      return :closed if suspended_selectors.any? { |sel| doc.at_css(sel) }

      # どれも無ければ open
      :open
    rescue
      :unknown
    end

    def cache_and(val, key)
      Rails.cache.write(key, val, expires_in: CACHE_TTL)
      val
    end
  end
end
