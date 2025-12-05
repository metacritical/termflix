# frozen_string_literal: true

require_relative '../utils'
require_relative '../streaming'

module Torrent
  module Catalog
    class VersionSelector
      def self.normalize_movie_name(name)
        # Remove year in parentheses: "Movie (2025)" -> "Movie"
        name = name.sub(/\s*\([0-9]{4}\)\s*$/, '')
        # Remove common quality/size indicators
        name = name.sub(/\s+(1080p|720p|4k|2160p|WEB-DL|BluRay|HDRip|x265|HEVC|BONE|5\.1).*$/i, '')
        # Remove source tags like [TPB], [YTS]
        name = name.sub(/^\s*\[.*?\]\s*/, '')
        # Clean up extra spaces
        name.strip
      end

      def self.extract_seeds_peers(result)
        seeds = result[:seeds] || 0
        peers = result[:peers] || 0

        # If not in result, try to extract from quality/extra fields
        if seeds == 0 && result[:quality] =~ /(\d+)\s*seeds?/i
          seeds = Regexp.last_match(1).to_i
        end

        if peers == 0 && result[:extra] =~ /(\d+)\s*peers?/i
          peers = Regexp.last_match(1).to_i
        end

        [seeds.to_i, peers.to_i]
      end

      def self.show_versions(movie_name, all_versions, debug: false)
        puts
        puts "#{Utils::Colors::GREEN}#{'━' * 60}#{Utils::Colors::RESET}"
        puts "#{Utils::Colors::BOLD}#{Utils::Colors::YELLOW}Available Versions: #{movie_name}#{Utils::Colors::RESET}"
        puts "#{Utils::Colors::GREEN}#{'━' * 60}#{Utils::Colors::RESET}"
        puts

        if all_versions.empty?
          puts "#{Utils::Colors::RED}No versions found#{Utils::Colors::RESET}"
          return 1
        end

        # Sort by seeds (descending), then by peers (descending)
        sorted_versions = all_versions.sort_by do |v|
          seeds, peers = extract_seeds_peers(v)
          [-seeds, -peers]  # Negative for descending sort
        end

        # Display all versions
        sorted_versions.each_with_index do |version, idx|
          item_num = idx + 1
          source = version[:source]
          name = version[:name]
          quality = version[:quality]
          size = version[:size]
          extra = version[:extra]
          source_color = get_source_color(source)

          seeds, peers = extract_seeds_peers(version)

          printf("#{Utils::Colors::BOLD}[%2d]#{Utils::Colors::RESET} #{source_color}[%s]#{Utils::Colors::RESET} ", item_num, source)
          puts "#{Utils::Colors::BOLD}#{name}#{Utils::Colors::RESET}"
          puts "     #{Utils::Colors::CYAN}Quality:#{Utils::Colors::RESET} #{quality} | #{Utils::Colors::CYAN}Size:#{Utils::Colors::RESET} #{size}"
          if seeds > 0 || peers > 0
            puts "     #{Utils::Colors::GREEN}Seeds:#{Utils::Colors::RESET} #{seeds} | #{Utils::Colors::GREEN}Peers:#{Utils::Colors::RESET} #{peers}"
          end
          puts "     #{Utils::Colors::YELLOW}#{extra}#{Utils::Colors::RESET}" unless extra.empty?
          puts
        end

        puts "#{Utils::Colors::GREEN}#{'━' * 60}#{Utils::Colors::RESET}"
        puts
        print "Select a version (1-#{sorted_versions.length}), or press Enter to go back: "

        selection = $stdin.gets
        return 0 unless selection
        selection = selection.chomp.strip

        case selection
        when /^\d+$/
          selection_num = selection.to_i
          if selection_num >= 1 && selection_num <= sorted_versions.length
            selected_version = sorted_versions[selection_num - 1]
            magnet = selected_version[:magnet].strip

            if debug
              puts "#{Utils::Colors::CYAN}#{'━' * 40}#{Utils::Colors::RESET}"
              puts "#{Utils::Colors::CYAN}DEBUG MODE#{Utils::Colors::RESET}"
              puts "#{Utils::Colors::CYAN}#{'━' * 40}#{Utils::Colors::RESET}"
              puts "#{Utils::Colors::YELLOW}Selected version:#{Utils::Colors::RESET}"
              puts "  Source: #{selected_version[:source]}"
              puts "  Name: #{selected_version[:name]}"
              puts "  Quality: #{selected_version[:quality]}"
              puts "  Size: #{selected_version[:size]}"
              seeds, peers = extract_seeds_peers(selected_version)
              puts "  Seeds: #{seeds} | Peers: #{peers}"
              puts "#{Utils::Colors::YELLOW}Magnet link:#{Utils::Colors::RESET}"
              puts "  #{magnet}"
              puts "#{Utils::Colors::CYAN}#{'━' * 40}#{Utils::Colors::RESET}"
              puts
            end

            unless magnet.start_with?('magnet:')
              puts "#{Utils::Colors::RED}Error:#{Utils::Colors::RESET} Invalid or missing magnet link"
              return 1
            end

            puts
            puts "#{Utils::Colors::GREEN}Streaming:#{Utils::Colors::RESET} #{selected_version[:name]}"
            puts

            return Streaming::Peerflix.stream(magnet, enable_subtitles: true, debug: debug)
          else
            puts "Invalid selection."
            return show_versions(movie_name, all_versions, debug: debug)
          end
        when '', 'b', 'back'
          puts "Going back..."
          return 2  # Special return code to indicate "go back"
        else
          puts "Invalid selection."
          return show_versions(movie_name, all_versions, debug: debug)
        end
      end

      private

      def self.get_source_color(source)
        case source
        when 'YTS'
          Utils::Colors::GREEN
        when 'TPB'
          Utils::Colors::YELLOW
        when 'EZTV'
          Utils::Colors::BLUE
        when 'YTSRS'
          Utils::Colors::CYAN
        when '1337x'
          Utils::Colors::MAGENTA
        else
          Utils::Colors::CYAN
        end
      end
    end
  end
end
