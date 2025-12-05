#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Torrent Streaming Tool - Stream torrents directly to mpv/vlc
# Self-contained Ruby version using only standard library
# Usage: torrent.rb <magnet_link|torrent_file|search_query>

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require_relative '../lib/torrent/utils'
require_relative '../lib/torrent/api'
require_relative '../lib/torrent/streaming'
require_relative '../lib/torrent/catalog'

module Torrent
  class CLI
    attr_accessor :debug_mode

    def initialize
      @debug_mode = false
    end

    def show_help
      puts <<~HELP
        #{Utils::Colors::BOLD}#{Utils::Colors::CYAN}Torrent Streaming Tool#{Utils::Colors::RESET}

        Stream torrents directly to mpv or VLC player using peerflix.

        #{Utils::Colors::BOLD}Usage:#{Utils::Colors::RESET}
          torrent.rb <magnet_link>
          torrent.rb <torrent_file>
          torrent.rb search <query>
          torrent.rb latest [movies|shows|all]
          torrent.rb trending [movies|shows|all]
          torrent.rb popular [movies|shows|all]
          torrent.rb catalog [genre]

        #{Utils::Colors::BOLD}Options:#{Utils::Colors::RESET}
          -h, --help          Show this help
          -l, --list          List available files in torrent
          -i, --index <num>   Select specific file by index
          -q, --quality       Auto-select best quality
          -s, --subtitles     Enable subtitle loading (auto-detected if available)
          -v, --verbose       Verbose output
              --debug         Show debug information (magnet links, etc.)

        #{Utils::Colors::BOLD}Commands:#{Utils::Colors::RESET}
          player <mpv|vlc>    Change default media player preference

        #{Utils::Colors::BOLD}Examples:#{Utils::Colors::RESET}
          torrent.rb "magnet:?xt=urn:btih:..."
          torrent.rb movie.torrent
          torrent.rb search "movie name"
          torrent.rb latest movies
          torrent.rb trending shows
          torrent.rb catalog action

        #{Utils::Colors::BOLD}Catalog Features:#{Utils::Colors::RESET}
          - Browse latest movies and TV shows (like Stremio)
          - View trending and popular content
          - Browse by genre/category
      HELP
    end

    def run(args)
      if args.empty? || args.include?('-h') || args.include?('--help')
        show_help
        return 0
      end

      @debug_mode = args.include?('--debug')
      args = args.reject { |a| a == '--debug' }

      # Handle player preference change
      if args[0] == 'player'
        if args[1] && %w[mpv vlc].include?(args[1])
          Utils::Config.set_player_preference(args[1])
          return 0
        else
          puts "#{Utils::Colors::RED}Error:#{Utils::Colors::RESET} Please specify a player (mpv or vlc)"
          puts "Usage: torrent.rb player <mpv|vlc>"
          return 1
        end
      end

      # Handle streaming
      if args[0] && (args[0].start_with?('magnet:') || File.exist?(args[0]))
        return Streaming::Peerflix.stream(args[0], enable_subtitles: args.include?('-s'), debug: @debug_mode)
      end

      # Handle commands
      case args[0]
      when 'latest'
        type = args[1] || 'all'
        case type
        when 'movies'
          api_functions = [
            -> { API::YTS.latest_movies(limit: 25) },
            -> { API::TPB.latest_movies },
            -> { API::YTSRS.latest(limit: 25) }
          ]
          Catalog::Display.show('🎬 Latest Movies', api_functions, page: 1, debug: @debug_mode)
        when 'shows'
          api_functions = [
            -> { API::EZTV.latest_shows(limit: 50) }
          ]
          Catalog::Display.show('📺 Latest TV Shows', api_functions, page: 1, debug: @debug_mode)
        else
          api_functions = [
            -> { API::YTS.latest_movies(limit: 15) },
            -> { API::YTSRS.latest(limit: 15) },
            -> { API::EZTV.latest_shows(limit: 20) }
          ]
          Catalog::Display.show('🎬 Latest Movies & Shows', api_functions, page: 1, debug: @debug_mode)
        end
      when 'trending'
        type = args[1] || 'all'
        case type
        when 'movies'
          api_functions = [
            -> { API::YTS.trending_movies(limit: 25) },
            -> { API::TPB.trending_movies },
            -> { API::YTSRS.trending(limit: 25) }
          ]
          Catalog::Display.show('🔥 Trending Movies', api_functions, page: 1, debug: @debug_mode)
        when 'shows'
          api_functions = [
            -> { API::EZTV.latest_shows(limit: 50) }
          ]
          Catalog::Display.show('🔥 Trending TV Shows', api_functions, page: 1, debug: @debug_mode)
        else
          api_functions = [
            -> { API::YTS.trending_movies(limit: 15) },
            -> { API::YTSRS.trending(limit: 15) },
            -> { API::EZTV.latest_shows(limit: 20) }
          ]
          Catalog::Display.show('🔥 Trending Content', api_functions, page: 1, debug: @debug_mode)
        end
      when 'popular'
        type = args[1] || 'all'
        case type
        when 'movies'
          api_functions = [
            -> { API::YTS.popular_movies(limit: 25) },
            -> { API::TPB.popular_movies },
            -> { API::YTSRS.popular(limit: 25) }
          ]
          Catalog::Display.show('⭐ Popular Movies', api_functions, page: 1, debug: @debug_mode)
        when 'shows'
          api_functions = [
            -> { API::EZTV.latest_shows(limit: 50) }
          ]
          Catalog::Display.show('⭐ Popular TV Shows', api_functions, page: 1, debug: @debug_mode)
        else
          api_functions = [
            -> { API::YTS.popular_movies(limit: 15) },
            -> { API::YTSRS.popular(limit: 15) },
            -> { API::EZTV.latest_shows(limit: 20) }
          ]
          Catalog::Display.show('⭐ Popular Content', api_functions, page: 1, debug: @debug_mode)
        end
      when 'catalog'
        genre = args[1]
        unless genre
          puts "#{Utils::Colors::BOLD}Available Genres:#{Utils::Colors::RESET}"
          puts "  action, adventure, animation, comedy, crime, documentary,"
          puts "  drama, family, fantasy, horror, mystery, romance,"
          puts "  sci-fi, thriller, war, western"
          puts
          puts "Usage: torrent.rb catalog <genre>"
          return 1
        end
        api_functions = [
          -> { API::YTS.by_genre(genre, limit: 25) },
          -> { API::YTSRS.by_genre(genre, limit: 25) }
        ]
        Catalog::Display.show("📚 #{genre.capitalize} Movies", api_functions, page: 1, debug: @debug_mode)
      when 'search'
        query = args[1]
        unless query
          puts "#{Utils::Colors::RED}Error:#{Utils::Colors::RESET} Please provide a search query"
          puts "Usage: torrent.rb search <query>"
          return 1
        end
        api_functions = [
          -> { API::YTS.search(query, limit: 10) },
          -> { API::TPB.search(query) },
          -> { API::EZTV.search(query, limit: 10) }
        ]
        Catalog::Display.show("🔍 Search: #{query}", api_functions, page: 1, debug: @debug_mode)
      else
        show_help
        return 1
      end
    end
  end
end

# Main entry point
if __FILE__ == $PROGRAM_NAME
  cli = Torrent::CLI.new
  result = cli.run(ARGV)
  exit(result || 0)
end
