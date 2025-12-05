# frozen_string_literal: true

require 'uri'
require 'json'
require_relative '../utils'
require_relative '../utils/http_client'

module Torrent
  module API
    class YTSRS
      BASE_URL = 'https://en.ytsrs.com/movies'

      def self.movies(genre: '', quality: '1080p', sort: 'seeds', limit: 20)
        params = "quality=#{quality}&sort=#{sort}"
        params += "&genre=#{genre}" unless genre.empty?
        url = "#{BASE_URL}?#{params}"

        html = Utils::HTTPClient.get(url, timeout: 10)
        return [] unless html && html.length > 100

        # Parse HTML using regex (like the Python script)
        results = []
        movie_pattern = /onclick=['"]openModal\((\d+),\s*["']([^"']+)["'],\s*["']([^"']+)["'],\s*["'](\d+)["']\)/

        movies = html.scan(movie_pattern)
        return [] if movies.empty?

        max_fetch = [limit, 10].min  # Only fetch details for first 10 to keep it fast

        movies.first(max_fetch).each do |movie_id, imdb_id, title, year|
          # Extract quality and poster from HTML around the movie card
          card_start = html.index("openModal(#{movie_id},")
          next unless card_start

          card_section = html[[0, card_start - 200].max..[card_start + 1000, html.length].min]

          quality_match = card_section.match(/<span[^>]*class="[^"]*movie-quality[^"]*"[^>]*>([^<]+)<\/span>/)
          movie_quality = quality_match ? quality_match[1].strip : quality

          poster_match = card_section.match(/<img[^>]*class="[^"]*movie-poster[^"]*"[^>]*src="([^"]+)"/)
          poster = poster_match ? poster_match[1] : 'N/A'

          # Fetch movie details to get hash
          detail_url = "https://en.ytsrs.com/?ajax=movie_details&movie_id=#{movie_id}&imdb_id=#{URI.encode_www_form_component(imdb_id)}&title=#{URI.encode_www_form_component(title)}&year=#{year}"

          begin
            detail_response = Utils::HTTPClient.get(detail_url, timeout: 2, headers: {
              'User-Agent' => 'Mozilla/5.0'
            })

            next unless detail_response

            detail_data = JSON.parse(detail_response) rescue nil
            next unless detail_data

            torrents = detail_data.dig('yts', 'data', 'movie', 'torrents') || []
            next if torrents.empty?

            # Find matching quality or use first
            torrent = torrents.find { |t| t['quality'] == movie_quality } || torrents.first
            next unless torrent['hash']

            results << {
              source: 'YTSRS',
              name: "#{title} (#{year})",
              magnet: "magnet:?xt=urn:btih:#{torrent['hash']}&dn=#{URI.encode_www_form_component(title)}",
              quality: torrent['quality'] || movie_quality,
              size: torrent['size'] || 'N/A',
              extra: "#{torrent['seeds'] || 0} seeds, #{torrent['peers'] || 0} peers",
              poster: poster,
              seeds: (torrent['seeds'] || 0).to_i,
              peers: (torrent['peers'] || 0).to_i
            }
          rescue => e
            # Skip on error - continue to next movie
            warn "YTSRS error for #{title}: #{e.message}" if ENV['TORRENT_DEBUG']
            next
          end
        end

        results
      end

      def self.latest(limit: 20, page: 1)
        movies(genre: '', quality: '1080p', sort: 'year', limit: limit)
      end

      def self.trending(limit: 20, page: 1)
        movies(genre: '', quality: '1080p', sort: 'seeds', limit: limit)
      end

      def self.popular(limit: 20, page: 1)
        movies(genre: '', quality: '1080p', sort: 'rating', limit: limit)
      end

      def self.by_genre(genre, limit: 20, page: 1)
        movies(genre: genre, quality: '1080p', sort: 'seeds', limit: limit)
      end
    end
  end
end
