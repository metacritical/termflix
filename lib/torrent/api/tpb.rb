# frozen_string_literal: true

require 'json'
require_relative '../utils'
require_relative '../utils/http_client'

module Torrent
  module API
    class TPB
      LATEST_URL = 'https://apibay.org/precompiled/data_top100_207.json'
      TRENDING_URL = 'https://apibay.org/precompiled/data_top100_201.json'
      POPULAR_URL = 'https://apibay.org/precompiled/data_top100_205.json'

      def self.latest_movies
        response = Utils::HTTPClient.get(LATEST_URL, timeout: 5)
        return [] unless response

        data = JSON.parse(response) rescue []
        return [] unless data.is_a?(Array)

        data.select do |item|
          # Validate info_hash - must be present, non-empty, and valid hex string (40 chars for SHA1)
          hash = item['info_hash']
          next false unless hash && !hash.empty?
          hash = hash.to_s.strip
          next false unless hash.length == 40
          next false unless hash.match?(/^[0-9a-fA-F]{40}$/)
          true
        end.map do |item|
          seeders = item['seeders'] || 0
          leechers = item['leechers'] || 0
          {
            source: 'TPB',
            name: item['name'] || '',
            magnet: "magnet:?xt=urn:btih:#{item['info_hash'].strip}",
            quality: "#{seeders} seeds",
            size: "#{(item['size'] || 0) / 1024 / 1024}MB",
            extra: 'Latest',
            poster: 'N/A',
            seeds: seeders.to_i,
            peers: (seeders.to_i + leechers.to_i)
          }
        end
      end

      def self.trending_movies
        response = Utils::HTTPClient.get(TRENDING_URL, timeout: 5)
        return [] unless response

        data = JSON.parse(response) rescue []
        return [] unless data.is_a?(Array)

        data.select do |item|
          # Validate info_hash - must be present, non-empty, and valid hex string (40 chars for SHA1)
          hash = item['info_hash']
          next false unless hash && !hash.empty?
          hash = hash.to_s.strip
          next false unless hash.length == 40
          next false unless hash.match?(/^[0-9a-fA-F]{40}$/)
          true
        end.map do |item|
          seeders = item['seeders'] || 0
          leechers = item['leechers'] || 0
          {
            source: 'TPB',
            name: item['name'] || '',
            magnet: "magnet:?xt=urn:btih:#{item['info_hash'].strip}",
            quality: "#{seeders} seeds",
            size: "#{(item['size'] || 0) / 1024 / 1024}MB",
            extra: 'Trending',
            poster: 'N/A',
            seeds: seeders.to_i,
            peers: (seeders.to_i + leechers.to_i)
          }
        end
      end

      def self.popular_movies
        response = Utils::HTTPClient.get(POPULAR_URL, timeout: 5)
        return [] unless response

        data = JSON.parse(response) rescue []
        return [] unless data.is_a?(Array)

        data.select do |item|
          # Validate info_hash - must be present, non-empty, and valid hex string (40 chars for SHA1)
          hash = item['info_hash']
          next false unless hash && !hash.empty?
          hash = hash.to_s.strip
          next false unless hash.length == 40
          next false unless hash.match?(/^[0-9a-fA-F]{40}$/)
          true
        end.map do |item|
          seeders = item['seeders'] || 0
          leechers = item['leechers'] || 0
          {
            source: 'TPB',
            name: item['name'] || '',
            magnet: "magnet:?xt=urn:btih:#{item['info_hash'].strip}",
            quality: "#{seeders} seeds",
            size: "#{(item['size'] || 0) / 1024 / 1024}MB",
            extra: 'Popular',
            poster: 'N/A',
            seeds: seeders.to_i,
            peers: (seeders.to_i + leechers.to_i)
          }
        end
      end

      def self.search(query)
        url = "https://apibay.org/q.php?q=#{URI.encode_www_form_component(query)}&cat=0"
        response = Utils::HTTPClient.get(url, timeout: 5)
        return [] unless response

        data = JSON.parse(response) rescue []
        return [] unless data.is_a?(Array)

        data.select do |item|
          # Validate info_hash - must be present, non-empty, and valid hex string (40 chars for SHA1)
          hash = item['info_hash']
          next false unless hash && !hash.empty?
          # Check if it's a valid hex string (40 chars for SHA1 hash)
          hash = hash.to_s.strip
          next false unless hash.length == 40
          # Validate it's hex (0-9, a-f, A-F)
          next false unless hash.match?(/^[0-9a-fA-F]{40}$/)
          true
        end.map do |item|
          seeders = item['seeders'] || 0
          leechers = item['leechers'] || 0
          {
            source: 'TPB',
            name: item['name'] || '',
            magnet: "magnet:?xt=urn:btih:#{item['info_hash'].strip}",
            quality: "#{seeders} seeds",
            size: "#{(item['size'] || 0) / 1024 / 1024}MB",
            extra: '',
            seeds: seeders.to_i,
            peers: (seeders.to_i + leechers.to_i)
          }
        end
      end
    end
  end
end
