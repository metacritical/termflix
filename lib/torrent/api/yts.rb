# frozen_string_literal: true

require 'json'
require_relative '../utils'
require_relative '../utils/http_client'

module Torrent
  module API
    class YTS
      BASE_URL = 'https://yts.mx/api/v2/list_movies.json'

      def self.latest_movies(limit: 50, page: 1)
        url = "#{BASE_URL}?limit=#{limit}&sort_by=date_added&order_by=desc&page=#{page}"
        response = Utils::HTTPClient.get(url, timeout: 3, headers: {
          'Accept' => 'application/json'
        })

        return [] unless response

        data = JSON.parse(response) rescue nil
        return [] unless data&.dig('status') == 'ok'

        movies = data.dig('data', 'movies') || []
        results = []

        movies.each do |movie|
          torrents = movie['torrents'] || []
          next if torrents.empty?

          torrent = torrents.first
          next unless torrent['hash']

          # YTS API doesn't provide seeds/peers in the list endpoint
          # We'll default to 0 and let users see all versions
          results << {
            source: 'YTS',
            name: "#{movie['title']} (#{movie['year']})",
            magnet: "magnet:?xt=urn:btih:#{torrent['hash']}",
            quality: torrent['quality'] || 'N/A',
            size: torrent['size'] || 'N/A',
            extra: movie['date_uploaded'] || 'N/A',
            poster: movie['medium_cover_image'] || 'N/A',
            seeds: 0,  # YTS API doesn't provide this in list endpoint
            peers: 0
          }
        end

        results
      end

      def self.trending_movies(limit: 50, page: 1)
        url = "#{BASE_URL}?limit=#{limit}&sort_by=download_count&order_by=desc&page=#{page}"
        response = Utils::HTTPClient.get(url, timeout: 3, headers: {
          'Accept' => 'application/json'
        })

        return [] unless response

        data = JSON.parse(response) rescue nil
        return [] unless data&.dig('status') == 'ok'

        movies = data.dig('data', 'movies') || []
        results = []

        movies.each do |movie|
          torrents = movie['torrents'] || []
          next if torrents.empty?

          torrent = torrents.first
          next unless torrent['hash']

          results << {
            source: 'YTS',
            name: "#{movie['title']} (#{movie['year']})",
            magnet: "magnet:?xt=urn:btih:#{torrent['hash']}",
            quality: torrent['quality'] || 'N/A',
            size: torrent['size'] || 'N/A',
            extra: movie['download_count'] || 0,
            poster: movie['medium_cover_image'] || 'N/A'
          }
        end

        results
      end

      def self.popular_movies(limit: 50, page: 1)
        url = "#{BASE_URL}?limit=#{limit}&sort_by=rating&order_by=desc&minimum_rating=7&page=#{page}"
        response = Utils::HTTPClient.get(url, timeout: 3, headers: {
          'Accept' => 'application/json'
        })

        return [] unless response

        data = JSON.parse(response) rescue nil
        return [] unless data&.dig('status') == 'ok'

        movies = data.dig('data', 'movies') || []
        results = []

        movies.each do |movie|
          torrents = movie['torrents'] || []
          next if torrents.empty?

          torrent = torrents.first
          next unless torrent['hash']

          results << {
            source: 'YTS',
            name: "#{movie['title']} (#{movie['year']}) - ⭐#{movie['rating'] || 'N/A'}",
            magnet: "magnet:?xt=urn:btih:#{torrent['hash']}",
            quality: torrent['quality'] || 'N/A',
            size: torrent['size'] || 'N/A',
            extra: movie['rating'] || 'N/A',
            poster: movie['medium_cover_image'] || 'N/A'
          }
        end

        results
      end

      def self.by_genre(genre, limit: 20)
        genre_map = {
          'action' => 'Action',
          'adventure' => 'Adventure',
          'animation' => 'Animation',
          'comedy' => 'Comedy',
          'crime' => 'Crime',
          'documentary' => 'Documentary',
          'drama' => 'Drama',
          'family' => 'Family',
          'fantasy' => 'Fantasy',
          'horror' => 'Horror',
          'mystery' => 'Mystery',
          'romance' => 'Romance',
          'sci-fi' => 'Sci-Fi',
          'scifi' => 'Sci-Fi',
          'science-fiction' => 'Sci-Fi',
          'thriller' => 'Thriller',
          'war' => 'War',
          'western' => 'Western'
        }

        genre_id = genre_map[genre.downcase] || genre

        url = "#{BASE_URL}?genre=#{URI.encode_www_form_component(genre_id)}&limit=#{limit}&sort_by=date_added&order_by=desc"
        response = Utils::HTTPClient.get(url, timeout: 10, retries: 1, retry_delay: 2, headers: {
          'Accept' => 'application/json'
        })

        return [] unless response

        data = JSON.parse(response) rescue nil
        return [] unless data&.dig('status') == 'ok'

        movies = data.dig('data', 'movies') || []
        results = []

        movies.each do |movie|
          torrents = movie['torrents'] || []
          next if torrents.empty?

          torrent = torrents.first
          next unless torrent['hash']

          genres = movie['genres'] || []
          genre_str = genres.join(', ')

          results << {
            source: 'YTS',
            name: "#{movie['title']} (#{movie['year']})",
            magnet: "magnet:?xt=urn:btih:#{torrent['hash']}",
            quality: torrent['quality'] || 'N/A',
            size: torrent['size'] || 'N/A',
            extra: genre_str,
            poster: movie['medium_cover_image'] || 'N/A'
          }
        end

        results
      end

      def self.search(query, limit: 10)
        url = "#{BASE_URL}?query_term=#{URI.encode_www_form_component(query)}&limit=#{limit}"
        response = Utils::HTTPClient.get(url, timeout: 5, headers: {
          'Accept' => 'application/json'
        })

        return [] unless response

        data = JSON.parse(response) rescue nil
        return [] unless data&.dig('status') == 'ok'

        movies = data.dig('data', 'movies') || []
        results = []

        movies.each do |movie|
          torrents = movie['torrents'] || []
          next if torrents.empty?

          # Find best quality torrent
          torrent = torrents.find { |t| t['quality'] == '1080p' } || torrents.first
          next unless torrent['hash']

          results << {
            source: 'YTS',
            name: "#{movie['title']} (#{movie['year']})",
            magnet: "magnet:?xt=urn:btih:#{torrent['hash']}",
            quality: torrent['quality'] || 'N/A',
            size: torrent['size'] || 'N/A',
            extra: ''
          }
        end

        results
      end
    end
  end
end
