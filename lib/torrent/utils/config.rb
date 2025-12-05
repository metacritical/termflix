# frozen_string_literal: true

require 'fileutils'
require_relative 'colors'

module Torrent
  module Utils
    class Config
      CONFIG_DIR = File.join(Dir.home, '.config')
      CONFIG_FILE = File.join(CONFIG_DIR, 'torrent_prefs')

      def self.get_player_preference
        FileUtils.mkdir_p(CONFIG_DIR) unless Dir.exist?(CONFIG_DIR)

        if File.exist?(CONFIG_FILE)
          player = File.readlines(CONFIG_FILE).find { |line| line.start_with?('PLAYER=') }
          if player
            player = player.chomp.split('=')[1]&.strip
            return player if %w[mpv vlc].include?(player)
          end
        end

        # First time setup
        if $stdin.tty? && File.exist?('/dev/tty')
          puts
          puts "#{Colors::YELLOW}#{'━' * 40}#{Colors::RESET}"
          puts "#{Colors::YELLOW}First time setup:#{Colors::RESET} Which media player would you like to use?"
          puts "  #{Colors::GREEN}1#{Colors::RESET}) mpv (recommended)"
          puts "  #{Colors::GREEN}2#{Colors::RESET}) VLC"
          print "#{Colors::YELLOW}Enter choice (1 or 2, default: 1):#{Colors::RESET} "

          begin
            choice = Timeout.timeout(10) { $stdin.gets.chomp }
          rescue Timeout::Error
            choice = '1'
          end

          choice = '1' if choice.empty?
          selected_player = (choice == '2') ? 'vlc' : 'mpv'

          unless system("command -v #{selected_player} > /dev/null 2>&1")
            puts "#{Colors::RED}Error:#{Colors::RESET} #{selected_player} is not installed."
            puts "Please install it first: #{Colors::CYAN}brew install #{selected_player}#{Colors::RESET}"
            puts "Defaulting to mpv..."
            selected_player = 'mpv'
          end

          File.write(CONFIG_FILE, "PLAYER=#{selected_player}\n")
          puts "#{Colors::GREEN}✓ Preference saved to:#{Colors::RESET} #{CONFIG_FILE}"
          puts "#{Colors::CYAN}Note:#{Colors::RESET} Edit this file to change your preference later."
          puts "#{Colors::YELLOW}#{'━' * 40}#{Colors::RESET}"
          puts
          return selected_player
        end

        'mpv'
      end

      def self.set_player_preference(player)
        FileUtils.mkdir_p(CONFIG_DIR) unless Dir.exist?(CONFIG_DIR)
        File.write(CONFIG_FILE, "PLAYER=#{player}\n")
        puts "#{Colors::GREEN}Player preference changed to:#{Colors::RESET} #{player}"
        puts "#{Colors::CYAN}Config saved to:#{Colors::RESET} #{CONFIG_FILE}"
      end
    end
  end
end
