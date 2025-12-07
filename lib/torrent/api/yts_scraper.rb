# frozen_string_literal: true

require 'uri'
require 'json'
require 'net/http'
require 'rexml/document'
require_relative '../utils'
require_relative '../utils/http_client'

module Torrent
  module API
    class YTSScraper
      # Try multiple working domains (yts.mx is not working)
      BASE_URLS = ['https://yts.rs', 'https://yts.hn']
      
      def self.find_working_domain
        BASE_URLS.each do |domain|
          begin
            test_url = "#{domain}/browse-movies"
            response = Utils::HTTPClient.get(test_url, timeout: 3, headers: {
              'User-Agent' => 'Mozilla/5.0'
            })
            return domain if response && response.length > 1000
          rescue
            next
          end
        end
        BASE_URLS.last # Fallback to last domain
      end
      
      BASE_URL = find_working_domain

      def self.scrape_movies(sort: 'date_added', order: 'desc', limit: 20, page: 1, genre: nil, quality: '1080p')
        # Build URL for browsing movies
        url = "#{BASE_URL}/browse-movies"
        params = []
        params << "sort_by=#{sort}" if sort
        params << "order_by=#{order}" if order
        params << "page=#{page}" if page > 1
        params << "genre=#{URI.encode_www_form_component(genre)}" if genre && !genre.empty?
        url += "?#{params.join('&')}" unless params.empty?

        html = Utils::HTTPClient.get(url, timeout: 15, headers: {
          'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language' => 'en-US,en;q=0.9'
        })

        return [] unless html && html.length > 1000

        results = []
        count = 0

        # Parse HTML using regex (simple approach without requiring nokogiri)
        # Look for movie links and extract data
        # YTS website structure: <a href="/movies/[slug]" class="browse-movie-link">
        movie_link_pattern = /<a[^>]+href="\/movies\/([^"]+)"[^>]*class="[^"]*browse-movie-link[^"]*"[^>]*>/
        movie_links = html.scan(movie_link_pattern)

        # Also try alternative pattern for movie boxes
        if movie_links.empty?
          movie_link_pattern = /<a[^>]+href="\/movies\/([^"]+)"[^>]*>/
          movie_links = html.scan(movie_link_pattern)
        end

        return [] if movie_links.empty?

        # Limit to requested number
        movie_links.first(limit).each do |(slug)|
          break if count >= limit

          begin
            # Fetch individual movie page to get torrent details
            movie_url = "#{BASE_URL}/movies/#{slug}"
            movie_html = Utils::HTTPClient.get(movie_url, timeout: 10, headers: {
              'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
              'Accept' => 'text/html,application/xhtml+xml'
            })

            next unless movie_html && movie_html.length > 500

            # Extract title and year
            title_match = movie_html.match(/<h1[^>]*>([^<]+)<\/h1>/)
            title = title_match ? title_match[1].strip : nil
            next unless title

            # Extract year
            year_match = movie_html.match(/<span[^>]*class="[^"]*year[^"]*"[^>]*>(\d{4})<\/span>/)
            year = year_match ? year_match[1] : nil

            # Extract poster
            poster_match = movie_html.match(/<img[^>]+class="[^"]*movie-poster[^"]*"[^>]+src="([^"]+)"/)
            poster = poster_match ? poster_match[1] : 'N/A'
            # Make absolute URL if relative
            poster = "#{BASE_URL}#{poster}" if poster != 'N/A' && poster.start_with?('/')

            # Extract torrent hash from download buttons or magnet links
            # Look for magnet links or hash in data attributes
            hash_match = movie_html.match(/magnet:\?xt=urn:btih:([a-fA-F0-9]{40})/)
            hash_match ||= movie_html.match(/data-hash="([a-fA-F0-9]{40})"/)
            hash_match ||= movie_html.match(/hash["\s]*[:=]["\s]*([a-fA-F0-9]{40})/)

            next unless hash_match

            hash = hash_match[1]

            # Try to find quality and size from torrent table
            quality_match = movie_html.match(/<span[^>]*class="[^"]*quality[^"]*"[^>]*>([^<]+)<\/span>/i)
            movie_quality = quality_match ? quality_match[1].strip : quality

            size_match = movie_html.match(/<span[^>]*class="[^"]*size[^"]*"[^>]*>([^<]+)<\/span>/i)
            size = size_match ? size_match[1].strip : 'N/A'

            # Extract seeds/peers if available
            seeds_match = movie_html.match(/<span[^>]*class="[^"]*seeds[^"]*"[^>]*>(\d+)<\/span>/i)
            seeds = seeds_match ? seeds_match[1].to_i : 0

            results << {
              source: 'YTS',
              name: "#{title}#{year ? " (#{year})" : ''}",
              magnet: "magnet:?xt=urn:btih:#{hash}",
              quality: movie_quality,
              size: size,
              extra: seeds > 0 ? "#{seeds} seeds" : 'N/A',
              poster: poster,
              seeds: seeds,
              peers: 0
            }

            count += 1
          rescue => e
            # Skip on error - continue to next movie
            warn "YTS scraper error for #{slug}: #{e.message}" if ENV['TORRENT_DEBUG']
            next
          end
        end

        results
      end

      def self.latest_movies(limit: 20, page: 1)
        scrape_movies(sort: 'date_added', order: 'desc', limit: limit, page: page)
      end

      def self.trending_movies(limit: 20, page: 1)
        scrape_movies(sort: 'download_count', order: 'desc', limit: limit, page: page)
      end

      def self.popular_movies(limit: 20, page: 1)
        scrape_movies(sort: 'rating', order: 'desc', limit: limit, page: page)
      end

      def self.by_genre(genre, limit: 20, page: 1)
        scrape_movies(genre: genre, sort: 'date_added', order: 'desc', limit: limit, page: page)
      end
    end
  end
end
