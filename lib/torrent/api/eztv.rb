# frozen_string_literal: true

require 'json'
require_relative '../utils'
require_relative '../utils/http_client'

module Torrent
  module API
    class EZTV
      BASE_URL = 'https://eztv.re/api/get-torrents'

      def self.latest_shows(limit: 50, page: 1)
        url = "#{BASE_URL}?limit=#{limit}&page=#{page}"
        response = Utils::HTTPClient.get(url, timeout: 5)
        return [] unless response

        data = JSON.parse(response) rescue nil
        return [] unless data

        count = data['torrents_count'] || 0
        return [] if count == 0

        torrents = data['torrents'] || []
        torrents.select { |t| t['magnet_url'] && !t['magnet_url'].empty? }.map do |torrent|
          {
            source: 'EZTV',
            name: torrent['title'] || '',
            magnet: torrent['magnet_url'],
            quality: "#{torrent['seeds'] || 0} seeds",
            size: "#{(torrent['size_bytes'] || 0) / 1024 / 1024}MB",
            extra: torrent['date_released_unix'] || 0,
            poster: 'N/A',
            seeds: (torrent['seeds'] || 0).to_i,
            peers: (torrent['peers'] || 0).to_i
          }
        end
      end

      def self.search(query, limit: 20)
        url = "#{BASE_URL}?imdb_id=&limit=#{limit}&page=1&query_string=#{URI.encode_www_form_component(query)}"
        response = Utils::HTTPClient.get(url, timeout: 5)
        return [] unless response

        data = JSON.parse(response) rescue nil
        return [] unless data

        count = data['torrents_count'] || 0
        return [] if count == 0

        torrents = data['torrents'] || []
        torrents.select { |t| t['magnet_url'] && !t['magnet_url'].empty? }.map do |torrent|
          {
            source: 'EZTV',
            name: torrent['title'] || '',
            magnet: torrent['magnet_url'],
            quality: "#{torrent['seeds'] || 0} seeds",
            size: "#{(torrent['size_bytes'] || 0) / 1024 / 1024}MB",
            extra: ''
          }
        end
      end
    end
  end
end
