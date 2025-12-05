# frozen_string_literal: true

require_relative 'colors'

module Torrent
  module Utils
    module Progress
      SPIN_CHARS = ['|', '/', '-', '\\'].freeze

      def self.spinner(message, &block)
        spin_idx = 0
        thread = Thread.new do
          loop do
            char = SPIN_CHARS[spin_idx % 4]
            print "\r#{Colors::CYAN}#{message}#{Colors::RESET} [#{char}]"
            sleep 0.2
            spin_idx += 1
          end
        end

        result = block.call
        thread.kill
        print "\r#{Colors::GREEN}✓ #{message}#{Colors::RESET}        \n"
        result
      end

      def self.bar(current, total, label: 'Progress', width: 20)
        return if total <= 0

        percent = (current * 100 / total)
        percent = 100 if percent > 100

        filled = (current * width / total)
        filled = width if filled > width

        bar_str = '🟩' * filled + '⬜' * (width - filled)
        printf("\r#{Colors::CYAN}%s:#{Colors::RESET} %s %d%% (%d/%d) ", label, bar_str, percent, current, total)
      end

      def self.show_spinner_char(message, index)
        char = SPIN_CHARS[index % 4]
        print "\r#{Colors::CYAN}#{message}#{Colors::RESET} [#{char}]"
      end
    end
  end
end
