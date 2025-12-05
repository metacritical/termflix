# frozen_string_literal: true

require 'net/http'
require 'net/https'
require 'uri'
require 'timeout'
require_relative 'colors'

module Torrent
  module Utils
    class HTTPClient
      DEFAULT_TIMEOUT = 10
      DEFAULT_USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'

      def self.get(url, headers: {}, timeout: DEFAULT_TIMEOUT, retries: 1, retry_delay: 2)
        # Try Net::HTTP first
        begin
          uri = URI(url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == 'https')
          http.read_timeout = timeout
          http.open_timeout = timeout

          request = Net::HTTP::Get.new(uri.request_uri)
          request['User-Agent'] = DEFAULT_USER_AGENT
          headers.each { |k, v| request[k] = v }

          attempts = 0
          begin
            http.start do |connection|
              response = connection.request(request)
              if response.is_a?(Net::HTTPSuccess)
                return response.body
              else
                warn "HTTP #{response.code}: #{response.message}" if ENV['TORRENT_DEBUG']
                break
              end
            end
          rescue => e
            attempts += 1
            if attempts <= retries
              sleep retry_delay
              retry
            end
            raise e
          end
        rescue Socket::ResolutionError, Errno::EHOSTUNREACH, Errno::ECONNREFUSED, Timeout::Error => e
          # Fallback to curl if Net::HTTP fails (DNS issues, network problems, etc.)
          warn "Net::HTTP failed (#{e.class}), trying curl fallback..." if ENV['TORRENT_DEBUG']
          return get_via_curl(url, headers: headers, timeout: timeout)
        rescue => e
          warn "HTTP Error: #{e.class}: #{e.message}" if ENV['TORRENT_DEBUG']
          # Try curl fallback for any other error
          return get_via_curl(url, headers: headers, timeout: timeout)
        end

        nil
      end

      def self.get_via_curl(url, headers: {}, timeout: DEFAULT_TIMEOUT)
        return nil unless system('command -v curl > /dev/null 2>&1')

        require 'open3'
        args = ['curl', '-s', '--max-time', timeout.to_s, '--connect-timeout', [timeout / 2, 2].max.to_s,
                '-H', "User-Agent: #{DEFAULT_USER_AGENT}"]
        headers.each { |k, v| args += ['-H', "#{k}: #{v}"] }
        args << url

        stdout, stderr, status = Open3.capture3(*args)
        return nil unless status.success?

        stdout.empty? ? nil : stdout
      end

      def self.post(url, data: nil, headers: {}, timeout: DEFAULT_TIMEOUT)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.read_timeout = timeout
        http.open_timeout = timeout

        request = Net::HTTP::Post.new(uri.request_uri)
        request['User-Agent'] = DEFAULT_USER_AGENT
        headers.each { |k, v| request[k] = v }
        request.body = data if data

        http.start do |connection|
          response = connection.request(request)
          return response.body if response.is_a?(Net::HTTPSuccess)
        end
      rescue => e
        warn "HTTP Error: #{e.message}" if ENV['TORRENT_DEBUG']
        nil
      end
    end
  end
end
