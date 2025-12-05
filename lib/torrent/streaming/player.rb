# frozen_string_literal: true

require_relative '../utils'
require_relative '../utils/config'

module Torrent
  module Streaming
    class Player
      def self.launch(video_path, subtitle_path: nil, player: nil)
        player ||= Utils::Config.get_player_preference
        video_dir = File.dirname(video_path)
        video_name = File.basename(video_path)

        Dir.chdir(video_dir) do
          args = [video_name]
          if subtitle_path
            sub_abs = File.realpath(subtitle_path) rescue subtitle_path
            sub_dir = File.dirname(sub_abs)
            if sub_dir == video_dir
              subtitle_arg = File.basename(sub_abs)
            else
              subtitle_arg = sub_abs
            end

            if player == 'vlc'
              args = [video_name, "--sub-file=#{subtitle_arg}"]
            else  # mpv
              args = [video_name, "--sub-file=#{subtitle_arg}", '--sid=1', '--sub-visibility=yes']
            end
          end

          spawn(player, *args, out: '/dev/null', err: '/dev/null')
        end
      end

      def self.is_running?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      end

      def self.wait_for_exit(pid)
        loop do
          return unless is_running?(pid)
          sleep 1
        end
      end
    end
  end
end
