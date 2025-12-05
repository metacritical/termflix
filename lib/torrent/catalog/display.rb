# frozen_string_literal: true

require 'thread'
require_relative '../utils'
require_relative '../utils/progress'
require_relative '../api'
require_relative 'pagination'
require_relative 'version_selector'

module Torrent
  module Catalog
    class Display
      def self.show(title, api_functions, page: 1, debug: false)
        puts "#{Utils::Colors::BOLD}#{Utils::Colors::YELLOW}#{title}#{Utils::Colors::RESET}\n"

        # Collect results from all API functions
        all_results = []
        threads = []
        mutex = Mutex.new

        puts "#{Utils::Colors::CYAN}Fetching data from sources...#{Utils::Colors::RESET}"

        api_functions.each do |api_func|
          source_name = get_source_name_from_func(api_func)

          # Run API function in thread
          thread = Thread.new do
            begin
              results = api_func.call
              mutex.synchronize do
                all_results.concat(results)
              end
              puts "\r#{Utils::Colors::GREEN}✓ Fetched from #{source_name}#{Utils::Colors::RESET}        \n"
            rescue => e
              warn "Error fetching from #{source_name}: #{e.message}" if debug
              puts "\r#{Utils::Colors::YELLOW}⚠ Error fetching from #{source_name}#{Utils::Colors::RESET}        \n"
            end
          end

          # Show spinner while waiting
          spin_idx = 0
          while thread.alive?
            Utils::Progress.show_spinner_char("Fetching from #{source_name}...", spin_idx)
            sleep 0.2
            spin_idx += 1
          end
          thread.join

          threads << thread
        end

        # Wait for all threads
        threads.each(&:join)

        puts "#{Utils::Colors::CYAN}Parsing results...#{Utils::Colors::RESET}"
        result_count = all_results.length
        puts "\r#{Utils::Colors::GREEN}✓ Parsed #{result_count} results#{Utils::Colors::RESET}        \n"

        if all_results.empty?
          puts "#{Utils::Colors::RED}No results found#{Utils::Colors::RESET}"
          puts "#{Utils::Colors::YELLOW}Note:#{Utils::Colors::RESET} This might be due to API timeouts or rate limiting."
          puts "Try again in a moment or use: #{Utils::Colors::CYAN}torrent.rb search \"query\"#{Utils::Colors::RESET}"
          return 1
        end

        puts

        # Group results by normalized movie name
        grouped_movies = {}
        all_results.each do |result|
          normalized_name = VersionSelector.normalize_movie_name(result[:name])
          grouped_movies[normalized_name] ||= []
          grouped_movies[normalized_name] << result
        end

        # Create unique movie list (one entry per normalized name)
        unique_movies = grouped_movies.map do |normalized_name, versions|
          # Use the version with most seeds as the representative
          best_version = versions.max_by do |v|
            seeds, _peers = VersionSelector.extract_seeds_peers(v)
            seeds
          end
          {
            normalized_name: normalized_name,
            display_name: best_version[:name],
            versions: versions,
            best_seeds: VersionSelector.extract_seeds_peers(best_version)[0]
          }
        end

        # Sort unique movies by best seeds (descending)
        unique_movies.sort_by! { |m| -m[:best_seeds] }

        # Calculate pagination for unique movies
        total = unique_movies.length
        start_idx, end_idx, total_pages = Pagination.calculate(total, page)

        puts "#{Utils::Colors::BOLD}#{Utils::Colors::GREEN}Found #{total} unique movies#{Utils::Colors::RESET} (#{result_count} total versions) (Page #{page}/#{total_pages})"
        puts "#{Utils::Colors::CYAN}Note:#{Utils::Colors::RESET} Select a movie to see all available versions from all sources"
        puts

        # Display unique movies
        index = start_idx
        display_count = 0

        while index < end_idx && index < total
          movie = unique_movies[index]
          next unless movie

          item_num = index + 1
          display_name = movie[:display_name]
          version_count = movie[:versions].length
          best_seeds = movie[:best_seeds]

          # Display movie with version count
          printf("#{Utils::Colors::BOLD}[%3d]#{Utils::Colors::RESET} ", item_num)
          puts "#{Utils::Colors::BOLD}#{display_name}#{Utils::Colors::RESET}"
          puts "     #{Utils::Colors::CYAN}Available versions:#{Utils::Colors::RESET} #{version_count} | #{Utils::Colors::GREEN}Best seeds:#{Utils::Colors::RESET} #{best_seeds}"
          puts

          index += 1
          display_count += 1
        end

        # Navigation
        puts
        puts "Navigation:"
        puts "  n or next - Next page" if page < total_pages
        puts "  p or prev - Previous page" if page > 1
        puts "  1-#{total} - Select torrent"
        puts

        # Get user selection
        print "Select a torrent (1-#{total})"
        print ", 'n' for next" if page < total_pages
        print ", 'p' for prev" if page > 1
        print ", or press Enter to cancel: "

        selection = $stdin.gets
        return 0 unless selection
        selection = selection.chomp.strip

        case selection.downcase
        when 'n', 'next'
          if page < total_pages
            ENV['CATALOG_PAGE'] = (page + 1).to_s
            return show(title, api_functions, page: page + 1, debug: debug)
          else
            puts "Already on last page."
            return show(title, api_functions, page: page, debug: debug)
          end
        when 'p', 'prev'
          if page > 1
            ENV['CATALOG_PAGE'] = (page - 1).to_s
            return show(title, api_functions, page: page - 1, debug: debug)
          else
            puts "Already on first page."
            return show(title, api_functions, page: page, debug: debug)
          end
        when /^\d+$/
          selection_num = selection.to_i
          if selection_num >= 1 && selection_num <= total
            selected_movie = unique_movies[selection_num - 1]
            all_versions = selected_movie[:versions]

            # Show version selection screen
            result = VersionSelector.show_versions(selected_movie[:display_name], all_versions, debug: debug)
            # If user went back (return code 2), show the movie list again
            if result == 2
              return show(title, api_functions, page: page, debug: debug)
            end
            return result
          else
            puts "Invalid selection."
            return show(title, api_functions, page: page, debug: debug)
          end
        when ''
          puts "Cancelled."
          return 0
        else
          puts "Invalid selection."
          return show(title, api_functions, page: page, debug: debug)
        end
      end

      private

      def self.get_source_name_from_func(api_func)
        # Try to determine source from the proc's source location or inspect
        begin
          source_code = api_func.source
        rescue
          begin
            source_code = api_func.inspect
          rescue
            source_code = ''
          end
        end

        if source_code =~ /YTSRS|ytsrs/i
          'YTSRS'
        elsif source_code =~ /YTS\.|API::YTS/i
          'YTS'
        elsif source_code =~ /TPB\.|API::TPB/i
          'TPB'
        elsif source_code =~ /EZTV\.|API::EZTV/i
          'EZTV'
        else
          'API'
        end
      end

      def self.get_source_color(source)
        case source
        when 'YTS'
          Utils::Colors::GREEN
        when 'TPB'
          Utils::Colors::YELLOW
        when 'EZTV'
          Utils::Colors::BLUE
        when '1337x'
          Utils::Colors::MAGENTA
        else
          Utils::Colors::CYAN
        end
      end

      def self.check_viu
        return false unless RUBY_PLATFORM.include?('darwin')
        system('command -v viu > /dev/null 2>&1')
      end
    end
  end
end
