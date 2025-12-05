# frozen_string_literal: true

require 'open3'
require 'fileutils'
require 'tempfile'
require 'timeout'
require_relative '../utils'
require_relative '../utils/config'
require_relative '../utils/progress'

module Torrent
  module Streaming
    class Peerflix
      def self.normalize_magnet_link(magnet)
        magnet = magnet.strip.gsub(/[\r\n]/, '')
        return magnet unless magnet.start_with?('magnet:')

        # Extract and lowercase the hash (peerflix may have issues with uppercase)
        if magnet =~ /btih:([a-fA-F0-9]+)/i
          hash = Regexp.last_match(1)
          hash_lower = hash.downcase
          magnet = magnet.sub(/btih:#{hash}/i, "btih:#{hash_lower}")
        end

        # Ensure proper format
        magnet = magnet.sub(/^magnet:/, 'magnet:?xt=urn:btih:') unless magnet.include?('?xt=urn:btih:')
        magnet
      end

      def self.has_subtitles?(source)
        stdout, stderr, status = Open3.capture3('peerflix', source, '--list')
        return false unless status.success?

        file_list = stdout
        subtitle_extensions = /\.(srt|vtt|ass|ssa|sub|idx)$/i
        file_list.lines.any? { |line| line =~ subtitle_extensions }
      end

      def self.normalize_path(path)
        return nil unless path
        # On macOS, /tmp is a symlink to /private/tmp
        # Normalize to /tmp for consistency
        path = path.sub(%r{^/private/tmp/}, '/tmp/')
        path
      end

      def self.extract_torrent_path(output_content)
        # Try multiple patterns to find the path
        if output_content =~ /info path\s+(\S+)/
          path = Regexp.last_match(1).strip
          path = path.split.first if path.include?(' ')
          path = normalize_path(path)
          return path if path && Dir.exist?(path)
        end

        # Try alternative patterns
        if output_content =~ %r{/tmp/torrent-stream/[a-zA-Z0-9]+}
          path = Regexp.last_match(0)
          path = normalize_path(path)
          return path if path && Dir.exist?(path)
        end

        # Also try /private/tmp pattern (macOS)
        if output_content =~ %r{/private/tmp/torrent-stream/[a-zA-Z0-9]+}
          path = Regexp.last_match(0)
          path = normalize_path(path)
          return path if path && Dir.exist?(path)
        end

        nil
      end

      def self.find_video_file(torrent_path)
        video_extensions = %w[.mp4 .mkv .avi .mov .webm .m4v .flv .wmv]
        video_files = []

        Dir.glob(File.join(torrent_path, '**', '*')).each do |file|
          next unless File.file?(file)
          ext = File.extname(file).downcase
          next unless video_extensions.include?(ext)

          size = File.size(file)
          next if size < 1_048_576  # At least 1MB

          video_files << { path: file, size: size }
        end

        # Return largest file (usually the main movie)
        video_files.max_by { |f| f[:size] }&.fetch(:path)
      end

      def self.find_subtitle_file(torrent_path)
        subtitle_extensions = %w[.srt .vtt .ass .ssa .sub .idx]
        subtitle_files = []

        Dir.glob(File.join(torrent_path, '**', '*')).each do |file|
          next unless File.file?(file)
          ext = File.extname(file).downcase
          next unless subtitle_extensions.include?(ext)

          size = File.size(file)
          next if size == 0  # Must have content

          subtitle_files << file
        end

        subtitle_files.first
      end

      def self.extract_peer_info(output_content)
        # Extract "from X/Y peers" pattern
        if output_content =~ /from\s+(\d+)\/(\d+)\s+peers/
          connected = Regexp.last_match(1).to_i
          total = Regexp.last_match(2).to_i
          return [connected, total]
        end
        [0, 0]
      end

      def self.stream(source, index: nil, enable_subtitles: false, debug: false)
        Peerflix.check_dependencies

        player = Utils::Config.get_player_preference
        source = normalize_magnet_link(source)

        if debug
          puts "#{Utils::Colors::CYAN}#{'━' * 40}#{Utils::Colors::RESET}"
          puts "#{Utils::Colors::CYAN}DEBUG: stream_peerflix#{Utils::Colors::RESET}"
          puts "#{Utils::Colors::CYAN}#{'━' * 40}#{Utils::Colors::RESET}"
          puts "#{Utils::Colors::YELLOW}Source (raw):#{Utils::Colors::RESET} '#{source}'"
          puts "#{Utils::Colors::YELLOW}Source length:#{Utils::Colors::RESET} #{source.length} characters"
          puts "#{Utils::Colors::YELLOW}Is magnet link:#{Utils::Colors::RESET} #{source.start_with?('magnet:') ? 'yes' : 'no'}"
          puts "#{Utils::Colors::YELLOW}Is file:#{Utils::Colors::RESET} #{File.exist?(source) ? 'yes' : 'no'}"
          if source =~ /btih:([a-f0-9]+)/i
            puts "#{Utils::Colors::YELLOW}Magnet hash:#{Utils::Colors::RESET} #{Regexp.last_match(1)}"
          end
          puts "#{Utils::Colors::CYAN}#{'━' * 40}#{Utils::Colors::RESET}"
          puts
        end

        unless source.start_with?('magnet:') || File.exist?(source)
          puts "#{Utils::Colors::RED}Error:#{Utils::Colors::RESET} Invalid torrent source: '#{source}'"
          puts "#{Utils::Colors::YELLOW}Expected:#{Utils::Colors::RESET} magnet link (magnet:?xt=...) or path to .torrent file"
          return 1
        end

        puts "#{Utils::Colors::GREEN}#{'━' * 40}#{Utils::Colors::RESET}"
        puts "#{Utils::Colors::GREEN}Streaming with peerflix to #{player}...#{Utils::Colors::RESET}"
        puts "#{Utils::Colors::GREEN}#{'━' * 40}#{Utils::Colors::RESET}"
        puts

        # Start peerflix
        temp_output = Tempfile.new('peerflix_output')
        temp_output.close

        args = ['-p', '0']
        args += ['-i', index.to_s] if index

        puts "#{Utils::Colors::CYAN}#{'━' * 40}#{Utils::Colors::RESET}"
        puts "#{Utils::Colors::YELLOW}Starting peerflix to download torrent files...#{Utils::Colors::RESET}"
        puts "#{Utils::Colors::CYAN}#{'━' * 40}#{Utils::Colors::RESET}"

        # Start peerflix in background
        pid = spawn('peerflix', source, *args, out: temp_output.path, err: temp_output.path)

        # Check if peerflix started successfully
        sleep 2
        begin
          Process.kill(0, pid)
        rescue Errno::ESRCH
          # Process died - check error
          error_output = File.read(temp_output.path) rescue ''
          if error_output =~ /Invalid data|Missing delimiter|parse-torrent|bencode/
            puts "#{Utils::Colors::RED}#{'━' * 40}#{Utils::Colors::RESET}"
            puts "#{Utils::Colors::RED}Error:#{Utils::Colors::RESET} peerflix failed to parse torrent metadata"
            puts "#{Utils::Colors::YELLOW}This is a peerflix compatibility issue with this specific torrent.#{Utils::Colors::RESET}"
            puts
            puts "#{Utils::Colors::CYAN}Possible reasons:#{Utils::Colors::RESET}"
            puts "  • Torrent metadata is corrupted or malformed"
            puts "  • Torrent is dead/invalid (no seeders, removed from trackers)"
            puts "  • peerflix's parser doesn't support this torrent's format"
            puts
            puts "#{Utils::Colors::CYAN}Magnet link:#{Utils::Colors::RESET}"
            puts "  #{source}"
            puts
            puts "#{Utils::Colors::CYAN}Note:#{Utils::Colors::RESET} The magnet link format is valid. This is a peerflix limitation."
            puts "#{Utils::Colors::CYAN}Solution:#{Utils::Colors::RESET} Try selecting a different torrent from the list."
            puts "#{Utils::Colors::RED}#{'━' * 40}#{Utils::Colors::RESET}"
            temp_output.unlink
            return 1
          end
        end

        # Wait for torrent path
        puts "#{Utils::Colors::CYAN}Waiting for peerflix to show torrent path...#{Utils::Colors::RESET}"
        torrent_path = nil
        max_wait = 25
        waited = 0

        while waited < max_wait
          if File.exist?(temp_output.path) && File.size(temp_output.path) > 0
            output_content = File.read(temp_output.path)
            torrent_path = extract_torrent_path(output_content)

            if torrent_path && Dir.exist?(torrent_path)
              puts "#{Utils::Colors::GREEN}#{'━' * 40}#{Utils::Colors::RESET}"
              puts "#{Utils::Colors::GREEN}✓ TORRENT PATH:#{Utils::Colors::RESET}"
              puts "#{Utils::Colors::CYAN}#{torrent_path}#{Utils::Colors::RESET}"
              puts "#{Utils::Colors::GREEN}#{'━' * 40}#{Utils::Colors::RESET}"
              break
            end
          end

          Utils::Progress.show_spinner_char("Waiting for torrent path...", waited)
          sleep 1
          waited += 1
        end

        if torrent_path.nil? || !Dir.exist?(torrent_path)
          puts
          puts "#{Utils::Colors::RED}Error:#{Utils::Colors::RESET} Could not determine torrent path"
          puts "#{Utils::Colors::YELLOW}Peerflix output for debugging:#{Utils::Colors::RESET}"
          puts "#{Utils::Colors::CYAN}#{'━' * 40}#{Utils::Colors::RESET}"
          if File.exist?(temp_output.path)
            puts File.readlines(temp_output.path).last(30).join
          end
          puts "#{Utils::Colors::CYAN}#{'━' * 40}#{Utils::Colors::RESET}"
          Process.kill('TERM', pid) rescue nil
          temp_output.unlink
          return 1
        end

        puts
        # Wait for files to download
        puts "#{Utils::Colors::CYAN}Waiting for files to download...#{Utils::Colors::RESET}"
        sleep 3

        # Find video file
        puts "#{Utils::Colors::CYAN}Searching for video file...#{Utils::Colors::RESET}"
        video_file = nil
        video_wait = 0
        max_video_wait = 30

        while video_wait < max_video_wait
          unless Dir.exist?(torrent_path)
            sleep 1
            video_wait += 1
            next
          end

          all_files = Dir.glob(File.join(torrent_path, '**', '*')).select { |f| File.file?(f) }
          if all_files.empty?
            Utils::Progress.show_spinner_char("Waiting for files to download...", video_wait)
            sleep 1
            video_wait += 1
            next
          end

          video_file = find_video_file(torrent_path)
          if video_file && File.exist?(video_file)
            puts "\r#{Utils::Colors::GREEN}✓ Video file found#{Utils::Colors::RESET}\n"
            break
          end

          Utils::Progress.show_spinner_char("Searching for video file...", video_wait)
          sleep 1
          video_wait += 1
        end

        if video_file.nil? || !File.exist?(video_file)
          puts
          puts "#{Utils::Colors::RED}#{'━' * 40}#{Utils::Colors::RESET}"
          puts "#{Utils::Colors::RED}Error:#{Utils::Colors::RESET} Could not find video file in torrent"
          puts "#{Utils::Colors::RED}#{'━' * 40}#{Utils::Colors::RESET}"
          puts "#{Utils::Colors::YELLOW}Torrent path:#{Utils::Colors::RESET} #{torrent_path}"
          puts
          puts "#{Utils::Colors::YELLOW}All files found (recursive):#{Utils::Colors::RESET}"
          found_any = false
          Dir.glob(File.join(torrent_path, '**', '*')).each do |file|
            next unless File.file?(file)
            found_any = true
            rel_path = file.sub("#{torrent_path}/", '')
            fsize = File.size(file)
            fname = File.basename(file)
            puts "  #{Utils::Colors::CYAN}→#{Utils::Colors::RESET} #{rel_path}"
            puts "    #{Utils::Colors::YELLOW}Size:#{Utils::Colors::RESET} #{fsize} bytes | #{Utils::Colors::YELLOW}Name:#{Utils::Colors::RESET} #{fname}"
          end
          unless found_any
            puts "  #{Utils::Colors::YELLOW}(no files found - torrent may still be downloading)#{Utils::Colors::RESET}"
            puts
            puts "#{Utils::Colors::CYAN}Note:#{Utils::Colors::RESET} This torrent may not have any video files, or files are still downloading."
            puts "#{Utils::Colors::CYAN}Try:#{Utils::Colors::RESET} Wait a moment and try again, or check the torrent contents manually."
          end
          puts "#{Utils::Colors::RED}#{'━' * 40}#{Utils::Colors::RESET}"
          Process.kill('TERM', pid) rescue nil
          temp_output.unlink
          return 1
        end

        # Normalize path to use /tmp instead of /private/tmp
        video_path = File.realpath(video_file) rescue video_file
        video_path = normalize_path(video_path) || video_file
        video_dir = File.dirname(video_path)
        video_name = File.basename(video_path)

        puts "#{Utils::Colors::GREEN}#{'━' * 40}#{Utils::Colors::RESET}"
        puts "#{Utils::Colors::GREEN}✓ Video file found:#{Utils::Colors::RESET} #{video_name}"
        puts "#{Utils::Colors::CYAN}Video directory:#{Utils::Colors::RESET} #{video_dir}"
        puts "#{Utils::Colors::CYAN}Full path:#{Utils::Colors::RESET} #{video_path}"
        puts "#{Utils::Colors::GREEN}#{'━' * 40}#{Utils::Colors::RESET}"
        puts

        # Find subtitle file
        subtitle_file = nil
        if enable_subtitles || has_subtitles?(source)
          subtitle_file = find_subtitle_file(torrent_path)
          if subtitle_file
            begin
              sub_abs = File.realpath(subtitle_file)
            rescue
              sub_abs = subtitle_file
            end
            sub_abs = normalize_path(sub_abs) || subtitle_file
            puts "#{Utils::Colors::GREEN}#{'━' * 40}#{Utils::Colors::RESET}"
            puts "#{Utils::Colors::GREEN}✓ SRT File Found:#{Utils::Colors::RESET} #{sub_abs}"
            puts "#{Utils::Colors::GREEN}#{'━' * 40}#{Utils::Colors::RESET}"
            puts
          end
        end

        # Buffer video before starting player
        puts "#{Utils::Colors::CYAN}#{'━' * 40}#{Utils::Colors::RESET}"
        puts "#{Utils::Colors::CYAN}Buffering video...#{Utils::Colors::RESET}"
        puts "#{Utils::Colors::CYAN}#{'━' * 40}#{Utils::Colors::RESET}"

        target_buffer_size = 52_428_800  # 50MB
        buffer_wait = 0
        max_buffer_wait = 300
        last_size = 0
        stalled_count = 0
        connected_peers = 0
        total_peers = 0

        while buffer_wait < max_buffer_wait
          unless File.exist?(video_path)
            sleep 1
            buffer_wait += 1
            next
          end

          current_size = File.size(video_path)

          # Extract peer information
          if File.exist?(temp_output.path) && File.size(temp_output.path) > 0
            output_content = File.read(temp_output.path)
            connected_peers, total_peers = extract_peer_info(output_content)
          end

          # Check if file is growing
          if current_size == last_size && current_size > 0
            stalled_count += 1
            if stalled_count > 10 && current_size >= target_buffer_size
              break
            end
          else
            stalled_count = 0
          end

          last_size = current_size

          # Show progress
          if current_size > 0
            progress_percent = (current_size * 100 / target_buffer_size)
            progress_percent = 100 if progress_percent > 100

            width = 20
            filled = (progress_percent * width / 100)
            filled = width if filled > width

            bar_str = '🟩' * filled + '⬜' * (width - filled)

            if total_peers > 0
              printf("\r#{Utils::Colors::CYAN}Buffering:#{Utils::Colors::RESET} %s %d%% (%d/%d peers) ", bar_str, progress_percent, connected_peers, total_peers)
            else
              printf("\r#{Utils::Colors::CYAN}Buffering:#{Utils::Colors::RESET} %s %d%% ", bar_str, progress_percent)
            end
          else
            if total_peers > 0
              printf("\r#{Utils::Colors::CYAN}Buffering...#{Utils::Colors::RESET} [0%%] (%d/%d peers) ", connected_peers, total_peers)
            else
              printf("\r#{Utils::Colors::CYAN}Buffering...#{Utils::Colors::RESET} [0%%]")
            end
          end

          # If we have enough buffer, proceed
          if current_size >= target_buffer_size
            puts
            puts "#{Utils::Colors::GREEN}#{'━' * 40}#{Utils::Colors::RESET}"
            puts "#{Utils::Colors::GREEN}✓ Buffer ready (#{current_size} bytes)#{Utils::Colors::RESET}"
            puts "#{Utils::Colors::CYAN}Connected to #{connected_peers}/#{total_peers} peers#{Utils::Colors::RESET}" if total_peers > 0
            puts "#{Utils::Colors::GREEN}#{'━' * 40}#{Utils::Colors::RESET}"
            break
          end

          sleep 1
          buffer_wait += 1
        end

        final_size = File.size(video_path) rescue 0
        if final_size < target_buffer_size
          puts
          puts "#{Utils::Colors::YELLOW}#{'━' * 40}#{Utils::Colors::RESET}"
          puts "#{Utils::Colors::YELLOW}⚠ Warning:#{Utils::Colors::RESET} Buffer not fully ready (#{final_size} bytes), but proceeding..."
          puts "#{Utils::Colors::CYAN}Connected to #{connected_peers}/#{total_peers} peers#{Utils::Colors::RESET}" if total_peers > 0
          puts "#{Utils::Colors::YELLOW}#{'━' * 40}#{Utils::Colors::RESET}"
        end
        puts

        # Launch player
        puts "#{Utils::Colors::GREEN}#{'━' * 40}#{Utils::Colors::RESET}"
        puts "#{Utils::Colors::GREEN}Launching #{player} from local directory...#{Utils::Colors::RESET}"
        puts "  #{Utils::Colors::CYAN}Directory:#{Utils::Colors::RESET} #{video_dir}"
        puts "  #{Utils::Colors::CYAN}Video:#{Utils::Colors::RESET} #{video_name}"
        if subtitle_file
          begin
            sub_abs = File.realpath(subtitle_file)
          rescue
            sub_abs = subtitle_file
          end
          sub_name = File.basename(sub_abs)
          sub_dir = File.dirname(sub_abs)
          if sub_dir == video_dir
            puts "  #{Utils::Colors::CYAN}Subtitle:#{Utils::Colors::RESET} #{sub_name}"
          else
            puts "  #{Utils::Colors::CYAN}Subtitle:#{Utils::Colors::RESET} #{subtitle_file}"
          end
        end
        puts "#{Utils::Colors::GREEN}#{'━' * 40}#{Utils::Colors::RESET}"
        puts

        # Change to video directory and launch player
        Dir.chdir(video_dir) do
          player_args = [video_name]
          if subtitle_file
            begin
              sub_abs = File.realpath(subtitle_file)
            rescue
              sub_abs = subtitle_file
            end
            sub_dir = File.dirname(sub_abs)
            if sub_dir == video_dir
              subtitle_arg = File.basename(sub_abs)
            else
              subtitle_arg = sub_abs
            end

            if player == 'vlc'
              player_args = [video_name, "--sub-file=#{subtitle_arg}"]
            else  # mpv
              player_args = [video_name, "--sub-file=#{subtitle_arg}", '--sid=1', '--sub-visibility=yes']
            end
          end

          player_pid = spawn(player, *player_args, out: '/dev/null', err: '/dev/null')
          puts "#{Utils::Colors::CYAN}Player started (PID: #{player_pid}). Peerflix running (PID: #{pid})#{Utils::Colors::RESET}"
          puts

          # Set up signal handlers for graceful cleanup
          cleanup_done = false
          cleanup_proc = proc do
            unless cleanup_done
              cleanup_done = true
              puts "\n#{Utils::Colors::YELLOW}Interrupted. Stopping peerflix...#{Utils::Colors::RESET}"
              begin
                Process.kill('TERM', pid)
              rescue
              end
              sleep 1
              begin
                Process.kill('KILL', pid)
              rescue
              end
              begin
                Process.wait(pid)
              rescue
              end
              temp_output.unlink
              exit 0
            end
          end

          Signal.trap('INT', cleanup_proc)
          Signal.trap('TERM', cleanup_proc)

          # Wait a moment for the process to potentially fork (especially VLC on macOS)
          sleep 2

          # Monitor player process - VLC/mpv may fork, so check by process name
          player_running = true
          check_count = 0

          while player_running
            # Check if any player process is running (by name, not just PID)
            # This handles cases where VLC/mpv fork and the original PID exits
            player_processes = nil

            if player == 'vlc'
              # Check for VLC processes - VLC on macOS might be "VLC" or "vlc" or in an app bundle
              begin
                stdout, _stderr, status = Open3.capture3('pgrep', '-i', 'vlc')
                player_processes = stdout.strip if status.success? && !stdout.strip.empty?
              rescue
              end

              # Try ps to find VLC (might be case-sensitive)
              if player_processes.nil? || player_processes.empty?
                begin
                  stdout, _stderr, status = Open3.capture3('ps', 'aux')
                  if status.success?
                    vlc_line = stdout.lines.find { |line| line =~ /[V]LC/i && !line.include?('grep') }
                    if vlc_line
                      player_processes = vlc_line.split[1]  # PID is second field
                    end
                  end
                rescue
                end
              end

              # Also check if video file is open (lsof on macOS)
              if (player_processes.nil? || player_processes.empty?) && system('command -v lsof > /dev/null 2>&1')
                begin
                  stdout, _stderr, status = Open3.capture3('lsof', video_path)
                  if status.success? && stdout.include?('vlc')
                    player_processes = 'open'  # Mark as running
                  end
                rescue
                end
              end
            else
              # Check for mpv processes
              begin
                stdout, _stderr, status = Open3.capture3('pgrep', 'mpv')
                player_processes = stdout.strip if status.success? && !stdout.strip.empty?
              rescue
              end

              # Also check if video file is open (lsof on macOS)
              if (player_processes.nil? || player_processes.empty?) && system('command -v lsof > /dev/null 2>&1')
                begin
                  stdout, _stderr, status = Open3.capture3('lsof', video_path)
                  if status.success? && stdout.include?('mpv')
                    player_processes = 'open'  # Mark as running
                  end
                rescue
                end
              end
            end

            # If no player processes found, player has exited
            if player_processes.nil? || player_processes.empty?
              # Double-check: wait a moment and check again (in case of brief process switch)
              sleep 1
              if player == 'vlc'
                begin
                  stdout, _stderr, status = Open3.capture3('pgrep', '-i', 'vlc')
                  player_processes = stdout.strip if status.success? && !stdout.strip.empty?
                rescue
                end
                if player_processes.nil? || player_processes.empty?
                  begin
                    stdout, _stderr, status = Open3.capture3('ps', 'aux')
                    if status.success?
                      vlc_line = stdout.lines.find { |line| line =~ /[V]LC/i && !line.include?('grep') }
                      player_processes = vlc_line.split[1] if vlc_line
                    end
                  rescue
                  end
                end
              else
                begin
                  stdout, _stderr, status = Open3.capture3('pgrep', 'mpv')
                  player_processes = stdout.strip if status.success? && !stdout.strip.empty?
                rescue
                end
              end

              if player_processes.nil? || player_processes.empty?
                player_running = false
                break
              end
            end

            # Player still running, continue monitoring
            sleep 1
            check_count += 1

            # Safety: if we've been checking for too long (10 minutes), break
            if check_count > 600
              puts "#{Utils::Colors::YELLOW}Warning:#{Utils::Colors::RESET} Monitoring timeout, stopping peerflix anyway"
              player_running = false
              break
            end
          end

          # Clear signal handlers
          Signal.trap('INT', 'DEFAULT')
          Signal.trap('TERM', 'DEFAULT')

          # Player exited, kill peerflix
          puts "#{Utils::Colors::CYAN}Player closed. Stopping peerflix...#{Utils::Colors::RESET}"
          begin
            Process.kill('TERM', pid)
          rescue
          end
          sleep 1
          begin
            Process.kill('KILL', pid)
          rescue
          end
          begin
            Process.wait(pid)
          rescue
          end
        end

        temp_output.unlink
        0
      end

      def self.check_dependencies
        unless system('command -v peerflix > /dev/null 2>&1')
          puts "#{Utils::Colors::RED}Error:#{Utils::Colors::RESET} peerflix not found."
          puts
          puts "Please install peerflix:"
          puts "  #{Utils::Colors::GREEN}npm install -g peerflix#{Utils::Colors::RESET}"
          puts
          puts "Or use: #{Utils::Colors::CYAN}brew install peerflix#{Utils::Colors::RESET}"
          exit 1
        end
      end
    end
  end
end
