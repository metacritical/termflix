#!/usr/bin/env bash
# Torrent streaming and playback module
# Orchestrates buffer monitoring, subtitle detection, and player control

# Source streaming modules (refactored Dec 2025)
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$MODULE_DIR/streaming/buffer_monitor.sh"
. "$MODULE_DIR/streaming/subtitle_manager.sh"
. "$MODULE_DIR/streaming/player.sh"  # Already sourced, keeping for clarity
. "$MODULE_DIR/streaming/mpv_transition.sh"  # NEW: For splash screen transitions

# Main streaming logic for peerflix and transmission-cli
#

# Note: calculate_optimal_buffer() is now in bin/modules/streaming/buffer_monitor.sh
# Function removed during Dec 2025 refactoring to reduce torrent.sh size


# Note: has_subtitles() is now in bin/modules/streaming/subtitle_manager.sh
# Function removed during Dec 2025 refactoring to reduce torrent.sh size


# Stream with peerflix - use peerflix's --subtitles flag properly
stream_peerflix() {
    local source="$1"
    local index="${2:-}"
    local enable_subtitles="${3:-false}"
    local movie_title="${4:-Termflix Stream}"
    
    # Get player preference (will ask if first time, but with timeout to prevent hanging)
    local player=$(get_player_preference)
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${GREEN}Streaming with peerflix to $player...${RESET}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
    
    # Validate source is a valid magnet link or file
    source=$(echo "$source" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Normalize magnet link: ensure hash is lowercase (peerflix may have issues with uppercase)
    if [[ "$source" =~ ^magnet: ]]; then
        # Extract and lowercase the hash
        local hash=$(echo "$source" | grep -oE 'btih:[a-fA-F0-9]+' | cut -d: -f2 | head -1)
        if [ -n "$hash" ]; then
            local hash_lower=$(echo "$hash" | tr '[:upper:]' '[:lower:]')
            # Replace uppercase hash with lowercase
            if [ "$hash" != "$hash_lower" ]; then
                 source="${source/btih:$hash/btih:$hash_lower}"
            fi
        fi
        # Ensure proper magnet link format
        if [[ ! "$source" =~ ^magnet:\?xt=urn:btih: ]]; then
            # Try to fix common issues
            source=$(echo "$source" | sed 's/^magnet:/magnet:?xt=urn:btih:/' | sed 's/btih:\([^&]*\)/btih:\1/')
        fi
        
        # Add common trackers if not present (helps peerflix connect to peers)
        # Some magnet links work with transmission but not peerflix because they lack trackers
        if ! echo "$source" | grep -q "&tr="; then
            local common_trackers=(
                "udp://tracker.openbittorrent.com:80/announce"
                "udp://tracker.opentrackr.org:1337/announce"
                "udp://tracker.coppersurfer.tk:6969/announce"
                "udp://tracker.leechers-paradise.org:6969/announce"
                "udp://tracker.internetwarriors.net:1337/announce"
                "udp://9.rarbg.to:2710/announce"
                "udp://9.rarbg.me:2710/announce"
                "udp://exodus.desync.com:6969/announce"
            )
            
            for tracker in "${common_trackers[@]}"; do
                # URL encode the tracker (magnet links need URL-encoded trackers)
                local encoded_tracker=$(echo "$tracker" | sed 's/:/%3A/g' | sed 's/\//%2F/g' | sed 's/ /%20/g')
                source="${source}&tr=${encoded_tracker}"
            done
        fi
    fi
    
    # Debug output
    if [ "$TORRENT_DEBUG" = true ]; then
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${CYAN}DEBUG: stream_peerflix${RESET}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${YELLOW}Source (raw):${RESET} '$source'"
        echo -e "${YELLOW}Source (cleaned):${RESET} '$(echo "$source" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')'"
        echo -e "${YELLOW}Source length:${RESET} ${#source} characters"
        echo -e "${YELLOW}Is magnet link:${RESET} $([[ "$source" =~ ^magnet: ]] && echo "yes" || echo "no")"
        echo -e "${YELLOW}Is file:${RESET} $([ -f "$source" ] && echo "yes" || echo "no")"
        if [[ "$source" =~ ^magnet: ]]; then
            local hash_debug=$(echo "$source" | grep -oE 'btih:[a-fA-F0-9]+' | cut -d: -f2 | head -1)
            echo -e "${YELLOW}Magnet hash:${RESET} $hash_debug"
            echo -e "${YELLOW}Normalized magnet:${RESET} $source"
        fi
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo
    fi
    
    if [[ ! "$source" =~ ^magnet: ]] && [ ! -f "$source" ]; then
        echo -e "${RED}Error:${RESET} Invalid torrent source: '$source'"
        echo -e "${YELLOW}Expected:${RESET} magnet link (magnet:?xt=...) or path to .torrent file"
        return 1
    fi
    
    local args=("-p" "8888")  # Fixed port for HTTP streaming
    
    if [ -n "$index" ]; then
        args+=("-i" "$index")
    fi
    
    # Add quiet flag to reduce verbose output
    args+=("-q")
    
    # Check for subtitles and find the subtitle file path
    local subtitle_file=""
    if [ "$enable_subtitles" = true ] || has_subtitles "$source" >/dev/null 2>&1; then
        echo -e "${CYAN}Checking for subtitles in torrent...${RESET}"
        
        # We need to get the torrent path first to find subtitle files
        # Run peerflix briefly to get the path, then restart with subtitles
        local temp_output=$(mktemp 2>/dev/null || echo "/tmp/peerflix_output_$$")
        
        # Start peerflix briefly to get the path (without auto-launch)
        # This will start downloading the torrent files including subtitles
        peerflix "$source" "${args[@]}" > "$temp_output" 2>&1 &
        local temp_pid=$!
        
        # Wait for peerflix to start and show the path
        echo -e "${YELLOW}Waiting for peerflix to initialize and start downloading...${RESET}"
        sleep 3
        
        # Extract the path from peerflix output
        local torrent_path=""
        local max_wait=15
        local waited=0
        while [ $waited -lt $max_wait ]; do
            if [ -f "$temp_output" ]; then
                # Try multiple patterns to find the path
                torrent_path=$(grep "info path" "$temp_output" 2>/dev/null | head -1 | sed 's/.*info path //' | tr -d '\r\n')
                
                # If not found, try looking for path patterns in the output
                if [ -z "$torrent_path" ]; then
                    torrent_path=$(grep -iE "(path|downloaded|stream)" "$temp_output" 2>/dev/null | grep -oE "/tmp/[^[:space:]]+" | head -1)
                fi
                
                if [ -n "$torrent_path" ] && [ -d "$torrent_path" ]; then
                    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                    echo -e "${GREEN}✓ TORRENT PATH FOUND:${RESET}"
                    echo -e "${CYAN}$torrent_path${RESET}"
                    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                    echo
                    echo -e "${YELLOW}You can manually verify subtitle files with:${RESET}"
                    echo -e "${CYAN}ls -la \"$torrent_path\"${RESET}"
                    echo -e "${CYAN}find \"$torrent_path\" -name '*.srt'${RESET}"
                    echo
                    break
                fi
            fi
            sleep 1
            waited=$((waited + 1))
        done
        
        # If still not found, show the raw output for debugging
        if [ -z "$torrent_path" ] || [ ! -d "$torrent_path" ]; then
            echo -e "${YELLOW}Warning:${RESET} Could not extract torrent path from peerflix output"
            echo -e "${YELLOW}Peerflix output (last 20 lines):${RESET}"
            tail -20 "$temp_output" 2>/dev/null | while IFS= read -r line; do
                echo "  $line"
            done
        fi
        
        # Wait a bit more for files to actually download (especially subtitle files)
        # Search recursively for subtitle files
        if [ -n "$torrent_path" ] && [ -d "$torrent_path" ]; then
            echo -e "${YELLOW}Waiting for subtitle files to download...${RESET}"
            echo -e "${CYAN}Searching recursively in:${RESET} $torrent_path"
            echo
            
            local download_wait=0
            local max_download_wait=15  # Increased wait time
            
            while [ $download_wait -lt $max_download_wait ]; do
                # List all files in the directory for debugging (recursively)
                if [ $download_wait -eq 0 ] || [ $((download_wait % 3)) -eq 0 ]; then
                    echo -e "${YELLOW}Files in torrent (attempt $((download_wait + 1))):${RESET}"
                    find "$torrent_path" -type f 2>/dev/null | head -10 | while IFS= read -r file; do
                        if [ -n "$file" ]; then
                            local fname=$(basename "$file")
                            local fsize=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
                            local rel_path="${file#$torrent_path/}"
                            echo -e "  ${CYAN}→${RESET} $fname (${fsize} bytes) [${rel_path}]"
                        fi
                    done
                    echo
                fi
                
                # Check if any subtitle files exist and have content (search recursively)
                local found_sub=$(find "$torrent_path" -type f -iname "*.srt" 2>/dev/null | head -1)
                if [ -z "$found_sub" ]; then
                    found_sub=$(find "$torrent_path" -type f \( -iname "*.vtt" -o -iname "*.ass" -o -iname "*.ssa" \) 2>/dev/null | head -1)
                fi
                
                if [ -n "$found_sub" ] && [ -f "$found_sub" ] && [ -s "$found_sub" ]; then
                    # File exists and has content - it's downloaded
                    subtitle_file=$(realpath "$found_sub" 2>/dev/null || echo "$found_sub")
                    local file_size=$(stat -f%z "$subtitle_file" 2>/dev/null || stat -c%s "$subtitle_file" 2>/dev/null || echo "0")
                    
                    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                    echo -e "${GREEN}✓ SRT FOUND!${RESET}"
                    echo -e "  ${CYAN}File:${RESET} $(basename "$subtitle_file")"
                    echo -e "  ${CYAN}Location:${RESET} $subtitle_file"
                    echo -e "  ${CYAN}Size:${RESET} ${file_size} bytes"
                    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                    break
                fi
                
                sleep 1
                download_wait=$((download_wait + 1))
            done
            
            if [ -z "$subtitle_file" ]; then
                echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                echo -e "${YELLOW}⚠ NO SUBTITLE FILE FOUND${RESET}"
                echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                echo -e "${YELLOW}Torrent path:${RESET} $torrent_path"
                echo -e "${YELLOW}All files in torrent (recursive):${RESET}"
                find "$torrent_path" -type f 2>/dev/null | while IFS= read -r file; do
                    local rel_path="${file#$torrent_path/}"
                    echo -e "  ${CYAN}→${RESET} $rel_path"
                done
                echo
            fi
        fi
        
        # Kill the temp peerflix process
        echo -e "${YELLOW}Stopping temporary peerflix instance...${RESET}"
        kill $temp_pid 2>/dev/null || true
        wait $temp_pid 2>/dev/null || true
        sleep 1  # Give it a moment to clean up
        
        rm -f "$temp_output" 2>/dev/null
    fi
    
    # Don't use peerflix auto-launch - play file directly from local directory
    # Start peerflix in background to download files
    # Note: Remove -q temporarily to get path info, or check output more carefully
    echo "DEBUG: Past subtitle check, preparing peerflix launch"
    local temp_output=$(mktemp 2>/dev/null || echo "/tmp/peerflix_output_$$")
    local peerflix_pid
    
    # Extract hash from magnet to clean specific cache
    if [[ "$source" =~ ^magnet: ]]; then
        local torrent_hash=$(echo "$source" | grep -oE 'btih:[a-fA-F0-9]+' | cut -d: -f2 | tr '[:upper:]' '[:lower:]' | head -1)
        if [ -n "$torrent_hash" ]; then
            # Clean this specific torrent's cache to prevent verification loop
            rm -rf "/tmp/torrent-stream/$torrent_hash" 2>/dev/null
            rm -f "/tmp/torrent-stream/${torrent_hash}.torrent" 2>/dev/null
            echo -e "${YELLOW}Cleared cache for torrent: ${torrent_hash:0:8}...${RESET}"
        fi
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${YELLOW}Starting peerflix to download torrent files...${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    # Build peerflix arguments - add --remove to clean up on exit
    local temp_args=()
    for arg in "${args[@]}"; do
        if [[ "$arg" != "-q" ]]; then
            temp_args+=("$arg")
        fi
    done
    temp_args+=("--remove")  # Clean up files when done
    
    # Peerflix uses HTTP streaming by default when -p (port) is specified
    # The -p 8888 flag is already in args array, which enables HTTP mode
    # No need for --mode flag (may not be supported in all versions)
    echo -e "${CYAN}Peerflix will stream via HTTP on port 8888${RESET}"
    
    echo "DEBUG: Peerflix args: ${temp_args[@]}" >&2
    peerflix "$source" "${temp_args[@]}" > "$temp_output" 2>&1 &
    peerflix_pid=$!
    echo "DEBUG: Peerflix launched with PID: $peerflix_pid"
    
    # Check if peerflix started successfully (wait a moment, then check if process is still running)
    sleep 2
    if ! kill -0 "$peerflix_pid" 2>/dev/null; then
        # Process died - check error output
        if [ -f "$temp_output" ]; then
            local error_output=$(cat "$temp_output" 2>/dev/null)
            if echo "$error_output" | grep -q "Invalid data\|Missing delimiter\|parse-torrent\|bencode\|Error\|Failed"; then
                echo -e "${RED}Error:${RESET} peerflix failed to handle this magnet link"
                echo ""
                
                # Automatically use transmission-cli as fallback if available
                if command -v transmission-cli &> /dev/null; then
                    echo -e "${CYAN}Switching to transmission-cli fallback...${RESET}"
                    echo ""
                    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                    echo -e "${CYAN}Streaming with transmission-cli...${RESET}"
                    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                    echo ""
                    
                    # Extract hash from magnet link to create unique subdirectory
                    local torrent_hash=""
                    if [[ "$source" =~ ^magnet: ]]; then
                        torrent_hash=$(echo "$source" | grep -oE 'btih:[a-fA-F0-9]+' | cut -d: -f2 | tr '[:upper:]' '[:lower:]' | head -1)
                    fi
                    
                    # If no hash found (shouldn't happen for magnet links), use a timestamp-based hash
                    if [ -z "$torrent_hash" ]; then
                        torrent_hash=$(echo "$source" | shasum -a 256 | cut -d' ' -f1 | cut -c1-40)
                    fi
                    
                    # Create hash-based subdirectory for this specific torrent (easier to search files)
                    local base_dir="/tmp/torrent-stream"
                    local download_dir="$base_dir/$torrent_hash"
                    mkdir -p "$download_dir" 2>/dev/null
                    
                    # Get player preference
                    local player=$(get_player_preference)
                    
                    echo -e "${CYAN}Download directory:${RESET} $download_dir"
                    echo -e "${CYAN}Torrent hash:${RESET} $torrent_hash"
                    echo -e "${CYAN}Player:${RESET} $player"
                    echo -e "${YELLOW}Note:${RESET} It may take a while to connect to peers and start downloading..."
                    echo ""
                    
                    # Capture transmission output to parse progress
                    local transmission_output=$(mktemp 2>/dev/null || echo "/tmp/transmission_output_$$")
                    
                    # Record start time to filter out old files from previous downloads
                    local start_time=$(date +%s)
                    
                    # Run transmission-cli with --download-dir flag using hash-based subdirectory
                    # Use --download-dir explicitly to ensure it's used (transmission-cli may have config file defaults)
                    # Note: transmission-cli may create subdirectories within the download directory
                    # We'll search recursively to find the actual video files
                    # Check for transmission config and temporarily override download directory if needed
                    local transmission_config_dir="$HOME/.config/transmission"
                    local transmission_config="$transmission_config_dir/settings.json"
                    local config_backup=""
                    local original_download_dir=""
                    
                    # Auto-create config directory and file if they don't exist
                    if [ ! -d "$transmission_config_dir" ]; then
                        mkdir -p "$transmission_config_dir" 2>/dev/null
                        echo -e "${CYAN}Created transmission config directory:${RESET} $transmission_config_dir"
                    fi
                    
                    if [ ! -f "$transmission_config" ]; then
                        # Create default config file with download-dir set to /tmp/torrent-transmission/
                        # Matching the exact format of the existing settings.json
                        cat > "$transmission_config" << 'EOF'

"download-dir": "/tmp/torrent-transmission/"
EOF
                        echo -e "${CYAN}Created transmission config file:${RESET} $transmission_config"
                    fi
                    
                    if [ -f "$transmission_config" ]; then
                        # Backup the config file
                        config_backup=$(mktemp 2>/dev/null || echo "/tmp/transmission_config_backup_$$.json")
                        cp "$transmission_config" "$config_backup" 2>/dev/null
                        
                        # Read current download-dir setting
                        if command -v jq &> /dev/null; then
                            original_download_dir=$(jq -r '.["download-dir"] // empty' "$transmission_config" 2>/dev/null)
                            
                            # Temporarily set download-dir to our hash-based directory
                            jq --arg dir "$download_dir" '.["download-dir"] = $dir' "$transmission_config" > "${transmission_config}.tmp" 2>/dev/null && \
                                mv "${transmission_config}.tmp" "$transmission_config" 2>/dev/null
                        elif command -v python3 &> /dev/null; then
                            # Fallback to Python if jq is not available
                            python3 << EOF 2>/dev/null
import json
import sys
try:
    with open("$transmission_config", 'r') as f:
        config = json.load(f)
    original_download_dir = config.get('download-dir', '')
    config['download-dir'] = '$download_dir'
    with open("$transmission_config", 'w') as f:
        json.dump(config, f, indent=4)
    print(original_download_dir)
except:
    pass
EOF
                            original_download_dir=$(python3 -c "import json; f=open('$transmission_config'); d=json.load(f); print(d.get('download-dir', ''))" 2>/dev/null || echo "")
                        else
                            # Fallback: use sed to modify JSON (less reliable but works for simple cases)
                            original_download_dir=$(grep -oE '"download-dir"[[:space:]]*:[[:space:]]*"[^"]*"' "$transmission_config" 2>/dev/null | cut -d'"' -f4 || echo "")
                            # Escape the directory path for sed
                            local escaped_dir=$(echo "$download_dir" | sed 's/[[\.*^$()+?{|]/\\&/g')
                            sed -i.bak "s|\"download-dir\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"download-dir\": \"$escaped_dir\"|g" "$transmission_config" 2>/dev/null
                            rm -f "${transmission_config}.bak" 2>/dev/null
                        fi
                        
                        echo -e "${CYAN}Note:${RESET} Temporarily overriding transmission config download directory"
                    fi
                    
                    # Run transmission-cli with both --config-dir and --download-dir to ensure it uses our modified config
                    local transmission_config_dir="$HOME/.config/transmission"
                    if [ -d "$transmission_config_dir" ]; then
                        transmission-cli --config-dir "$transmission_config_dir" --download-dir "$download_dir" "$source" > "$transmission_output" 2>&1 &
                    else
                        transmission-cli --download-dir "$download_dir" "$source" > "$transmission_output" 2>&1 &
                    fi
                    local transmission_pid=$!
                    
                    # Wait a moment for transmission-cli to start and check if it's still running
                    sleep 2
                    
                    # Verify the download directory exists and is writable
                    if [ ! -d "$download_dir" ] || [ ! -w "$download_dir" ]; then
                        echo -e "${YELLOW}Warning:${RESET} Download directory may not be accessible: $download_dir"
                        echo -e "${CYAN}Creating directory...${RESET}"
                        mkdir -p "$download_dir" 2>/dev/null || {
                            echo -e "${RED}Error:${RESET} Cannot create download directory"
                            kill $transmission_pid 2>/dev/null || true
                            # Restore original transmission config if we modified it
                            if [ -n "$config_backup" ] && [ -f "$config_backup" ]; then
                                cp "$config_backup" "$transmission_config" 2>/dev/null
                                rm -f "$config_backup" 2>/dev/null
                            fi
                            rm -f "$transmission_output" 2>/dev/null
                            rm -f "$temp_output" 2>/dev/null
                            return 1
                        }
                    fi
                    
                    # Check if transmission-cli process is still running
                    if ! kill -0 "$transmission_pid" 2>/dev/null; then
                        echo -e "${RED}Error:${RESET} transmission-cli failed to start"
                        if [ -f "$transmission_output" ]; then
                            echo -e "${YELLOW}Transmission output:${RESET}"
                            cat "$transmission_output" | head -20
                        fi
                        # Restore original transmission config if we modified it
                        if [ -n "$config_backup" ] && [ -f "$config_backup" ]; then
                            cp "$config_backup" "$transmission_config" 2>/dev/null
                            rm -f "$config_backup" 2>/dev/null
                        fi
                        rm -f "$transmission_output" 2>/dev/null
                        rm -f "$temp_output" 2>/dev/null
                        return 1
                    fi
                    
                    # Check for immediate errors in output
                    if [ -f "$transmission_output" ]; then
                        local error_check=$(grep -iE "(error|failed|cannot|unable)" "$transmission_output" 2>/dev/null | head -3)
                        if [ -n "$error_check" ]; then
                            echo -e "${YELLOW}Warning:${RESET} Possible errors detected:"
                            echo "$error_check" | while IFS= read -r line; do
                                echo -e "  ${YELLOW}→${RESET} $line"
                            done
                            echo ""
                        fi
                    fi
                    
                    echo -e "${GREEN}Transmission started (PID: $transmission_pid)${RESET}"
                    echo -e "${CYAN}Connecting to peers and downloading metadata...${RESET}"
                    echo -e "${CYAN}This typically takes 8-30 seconds depending on tracker response.${RESET}"
                    echo ""
                    
                    # Set up SIGINT trap to handle Ctrl+C gracefully
                    _cleanup_transmission() {
                        echo ""  # New line after spinner
                        echo -e "${YELLOW}⚠ Cancelled by user${RESET}"
                        
                        # Kill transmission process
                        if [ -n "$transmission_pid" ] && kill -0 "$transmission_pid" 2>/dev/null; then
                            echo -e "${CYAN}Stopping transmission-cli...${RESET}"
                            kill -TERM "$transmission_pid" 2>/dev/null
                            sleep 1
                            # Force kill if still running
                            kill -0 "$transmission_pid" 2>/dev/null && kill -9 "$transmission_pid" 2>/dev/null
                        fi
                        
                        # Restore original transmission config if we modified it
                        if [ -n "$config_backup" ] && [ -f "$config_backup" ]; then
                            cp "$config_backup" "$transmission_config" 2>/dev/null
                            rm -f "$config_backup" 2>/dev/null
                        fi
                        
                        # Clean up temp files
                        rm -f "$transmission_output" 2>/dev/null
                        rm -f "$temp_output" 2>/dev/null
                        
                        # Remove the trap before returning
                        trap - INT
                        
                        # Return to catalog instead of exiting
                        echo -e "${CYAN}Returning to catalog...${RESET}"
                        sleep 1
                        return 1
                    }
                    
                    # Register the trap
                    trap '_cleanup_transmission' INT
                    
                    # Wait a bit for transmission to recognize the torrent and start downloading
                    # Based on user testing: ~4s to recognize torrent, ~8s to show progress
                    echo -e "${CYAN}Waiting for transmission to initialize...${RESET}"
                    echo -e "${YELLOW}Tip: Press ${BOLD}Ctrl+C${RESET}${YELLOW} to cancel${RESET}"
                    sleep 5
                    
                    # Wait for video file to appear - transmission-cli takes time to connect to peers
                    # Increased timeout significantly: 5 minutes (600 iterations * 0.5s)
                    # User testing shows ~32s total startup time, so 5 minutes is safe
                    local video_file=""
                    local video_wait=0
                    local max_video_wait=600  # 5 minutes * 60 / 0.5
                    
                    # Also check if transmission process is still running during the wait
                    
                    while [ $video_wait -lt $max_video_wait ]; do
                        # Find the largest video file in the hash-specific directory
                        # This ensures we only find files from this specific torrent
                        video_file=$(find "$download_dir" -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.m4v" \) 2>/dev/null | \
                            while IFS= read -r file; do
                                if [ -f "$file" ] && [ -s "$file" ]; then
                                    # Check if file was modified after transmission started
                                    # Use modification time (mtime) - on macOS use stat -f %m, on Linux use stat -c %Y
                                    local file_mtime=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo "0")
                                    
                                    # Only consider files created/modified after transmission started
                                    # Allow 2 seconds buffer for file system timing
                                    if [ "$file_mtime" -ge $((start_time - 2)) ]; then
                                        local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
                                        echo "$size|$file"
                                    fi
                                fi
                            done | sort -t'|' -k1 -rn | head -1 | cut -d'|' -f2)
                        
                        if [ -n "$video_file" ] && [ -f "$video_file" ] && [ -s "$video_file" ]; then
                            local file_size=$(stat -f%z "$video_file" 2>/dev/null || stat -c%s "$video_file" 2>/dev/null || echo "0")
                            if [ "$file_size" -gt 1048576 ]; then  # 1MB minimum
                                break
                            fi
                        fi
                        
                        # Charm-style dual spinner
                        local charm_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
                        local charm_len=${#charm_chars[@]}
                        local idx1=$(( (charm_len - (video_wait % charm_len)) % charm_len ))
                        local idx2=$(( video_wait % charm_len ))
                        # Show progress with elapsed time
                        local elapsed_secs=$((video_wait / 2))
                        printf "\r${MAGENTA}${charm_chars[$idx1]}${CYAN}${charm_chars[$idx2]}${RESET} Waiting for video file... ${PURPLE}[${CYAN}%ds${PURPLE}]${RESET}" "$elapsed_secs"
                        
                        # Check if transmission process is still running
                            if ! kill -0 "$transmission_pid" 2>/dev/null; then
                                echo ""
                                echo -e "${RED}Error:${RESET} transmission-cli process died unexpectedly"
                                if [ -f "$transmission_output" ]; then
                                    echo -e "${YELLOW}Last transmission output:${RESET}"
                                    tail -30 "$transmission_output" | while IFS= read -r line; do
                                        echo "  $line"
                                    done
                                fi
                                # Restore original transmission config if we modified it
                                if [ -n "$config_backup" ] && [ -f "$config_backup" ]; then
                                    cp "$config_backup" "$transmission_config" 2>/dev/null
                                    rm -f "$config_backup" 2>/dev/null
                                fi
                                rm -f "$transmission_output" 2>/dev/null
                                rm -f "$temp_output" 2>/dev/null
                                return 1
                            fi
                        
                        sleep 0.5
                        video_wait=$((video_wait + 1))
                    done
                    
                    # Remove SIGINT trap now that wait loop is complete
                    trap - INT
                    
                    if [ -z "$video_file" ] || [ ! -f "$video_file" ]; then
                        echo ""
                        echo -e "${RED}Error:${RESET} Could not find video file after 5 minutes"
                        
                        # Check if transmission is still running
                        if ! kill -0 "$transmission_pid" 2>/dev/null; then
                            echo -e "${YELLOW}Transmission process is not running.${RESET}"
                            if [ -f "$transmission_output" ]; then
                                echo -e "${YELLOW}Transmission output:${RESET}"
                                tail -50 "$transmission_output" | while IFS= read -r line; do
                                    echo "  $line"
                                done
                            fi
                        else
                            echo -e "${CYAN}Transmission is still running. Checking download directory...${RESET}"
                            echo -e "${CYAN}Directory:${RESET} $download_dir"
                            if [ -d "$download_dir" ]; then
                                echo -e "${CYAN}Files in directory:${RESET}"
                                find "$download_dir" -type f 2>/dev/null | head -10 | while IFS= read -r file; do
                                    if [ -n "$file" ]; then
                                        local fname=$(basename "$file")
                                        local fsize=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
                                        echo "  → $fname (${fsize} bytes)"
                                    fi
                                done
                            else
                                echo -e "${YELLOW}Directory does not exist:${RESET} $download_dir"
                            fi
                            
                            # Show recent transmission output
                            if [ -f "$transmission_output" ]; then
                                echo ""
                                echo -e "${CYAN}Recent transmission output:${RESET}"
                                tail -20 "$transmission_output" | while IFS= read -r line; do
                                    echo "  $line"
                                done
                            fi
                        fi
                        
                        kill $transmission_pid 2>/dev/null || true
                        # Restore original transmission config if we modified it
                        if [ -n "$config_backup" ] && [ -f "$config_backup" ]; then
                            cp "$config_backup" "$transmission_config" 2>/dev/null
                            rm -f "$config_backup" 2>/dev/null
                        fi
                        rm -f "$transmission_output" 2>/dev/null
                        rm -f "$temp_output" 2>/dev/null
                        return 1
                    fi
                    
                    local video_path=$(realpath "$video_file" 2>/dev/null || echo "$video_file")
                    local video_dir=$(dirname "$video_path")
                    local video_name=$(basename "$video_path")
                    
                    echo ""
                    echo -e "${GREEN}✓ Video file found:${RESET} $video_name"
                    echo ""
                    
                    # Wait for buffer (10% progress or 50MB, whichever comes first)
                    echo -e "${CYAN}Buffering video (waiting for 10% progress)...${RESET}"
                    local target_progress=10  # 10% progress
                    local target_buffer_size=52428800  # 50MB fallback
                    local buffer_wait=0
                    local max_buffer_wait=300  # 5 minutes max
                    local last_size=0
                    local last_progress=0
                    local current_progress=0
                    local connected_peers=0
                    local total_peers=0
                    local download_speed=""
                    local last_update_time=$(date +%s)
                    
                    while [ $buffer_wait -lt $max_buffer_wait ]; do
                        # Parse progress from transmission output (check more frequently)
                        if [ -f "$transmission_output" ]; then
                            # Look for "Progress: X.X%" pattern
                            local progress_line=$(grep "Progress:" "$transmission_output" 2>/dev/null | tail -1)
                            if [ -n "$progress_line" ]; then
                                # Extract percentage: "Progress: 18.0%" -> 18.0
                                current_progress=$(echo "$progress_line" | grep -oE "Progress: [0-9]+\.[0-9]+%" | grep -oE "[0-9]+\.[0-9]+" | head -1)
                                # Extract peers: "dl from 18 of 49 peers" -> 18 and 49
                                local peer_match=$(echo "$progress_line" | grep -oE "dl from [0-9]+ of [0-9]+ peers" 2>/dev/null)
                                if [ -n "$peer_match" ]; then
                                    connected_peers=$(echo "$peer_match" | grep -oE "[0-9]+" | head -1)
                                    total_peers=$(echo "$peer_match" | grep -oE "[0-9]+" | tail -1)
                                fi
                                # Extract download speed: "(1.38 MB/s)" or "(3.63 MB/s)"
                                download_speed=$(echo "$progress_line" | grep -oE "\([0-9]+\.[0-9]+ [A-Z]+/s\)" | head -1)
                            fi
                        fi
                        
                        # Check file size (more reliable and updates frequently)
                        local current_size=$(stat -f%z "$video_path" 2>/dev/null || stat -c%s "$video_path" 2>/dev/null || echo "0")
                        local size_mb=$((current_size / 1048576))
                        local size_display=""
                        if [ "$current_size" -gt 1048576 ]; then
                            size_display="${size_mb} MB"
                        elif [ "$current_size" -gt 1024 ]; then
                            size_display="$((current_size / 1024)) KB"
                        else
                            size_display="${current_size} B"
                        fi
                        
                        # Calculate download rate (bytes per second)
                        local current_time=$(date +%s)
                        local time_diff=$((current_time - last_update_time))
                        local size_diff=$((current_size - last_size))
                        local bytes_per_sec=0
                        if [ "$time_diff" -gt 0 ] && [ "$size_diff" -gt 0 ]; then
                            bytes_per_sec=$((size_diff / time_diff))
                        fi
                        local speed_display=""
                        if [ "$bytes_per_sec" -gt 0 ]; then
                            if [ "$bytes_per_sec" -gt 1048576 ]; then
                                if command -v bc &> /dev/null; then
                                    speed_display="$(echo "scale=2; $bytes_per_sec / 1048576" | bc) MB/s"
                                else
                                    speed_display="$((bytes_per_sec / 1048576)) MB/s"
                                fi
                            elif [ "$bytes_per_sec" -gt 1024 ]; then
                                if command -v bc &> /dev/null; then
                                    speed_display="$(echo "scale=2; $bytes_per_sec / 1024" | bc) KB/s"
                                else
                                    speed_display="$((bytes_per_sec / 1024)) KB/s"
                                fi
                            else
                                speed_display="${bytes_per_sec} B/s"
                            fi
                        fi
                        
                        # Show progress with multiple indicators
                        if [ -n "$current_progress" ] && [ "$current_progress" != "0" ]; then
                            local progress_int=$(echo "$current_progress" | cut -d. -f1)
                            
                            local width=20
                            local filled=$((progress_int * width / 100))
                            if [ "$filled" -gt "$width" ]; then
                                filled=$width
                            fi
                            
                            local bar=""
                            local i=0
                            while [ $i -lt $filled ]; do
                                bar="${bar}🟩"
                                i=$((i + 1))
                            done
                            while [ $i -lt $width ]; do
                                bar="${bar}⬜"
                                i=$((i + 1))
                            done
                            
                            # Build comprehensive progress display
                            local progress_display="${current_progress}%"
                            if [ -n "$download_speed" ]; then
                                progress_display="${progress_display} $download_speed"
                            elif [ -n "$speed_display" ] && [ "$bytes_per_sec" -gt 0 ]; then
                                progress_display="${progress_display} (~$speed_display)"
                            fi
                            if [ "$total_peers" -gt 0 ]; then
                                progress_display="${progress_display} | ${connected_peers}/${total_peers} peers"
                            fi
                            if [ "$current_size" -gt 0 ]; then
                                progress_display="${progress_display} | ${size_display} downloaded"
                            fi
                            
                            printf "\r${CYAN}Buffering:${RESET} %s %s" "$bar" "$progress_display"
                            
                            # Write status to file for inline UI (if exported)
                            [[ -n "$TERMFLIX_BUFFER_STATUS" ]] && \
                                echo "${progress_int:-0}|${bytes_per_sec:-0}|${connected_peers:-0}|${total_peers:-0}|${size_mb:-0}|BUFFERING" > "$TERMFLIX_BUFFER_STATUS"
                            
                            # Check if we have 10% progress
                            if [ "$progress_int" -ge "$target_progress" ]; then
                                echo ""
                                echo -e "${GREEN}✓ Buffer ready (${current_progress}% progress, ${size_display} downloaded)${RESET}"
                                [[ -n "$TERMFLIX_BUFFER_STATUS" ]] && echo "${progress_int}|${bytes_per_sec}|${connected_peers}|${total_peers}|${size_mb}|READY" > "$TERMFLIX_BUFFER_STATUS"
                                if [ "$total_peers" -gt 0 ]; then
                                    echo -e "${CYAN}Connected to ${connected_peers}/${total_peers} peers${RESET}"
                                fi
                                break
                            fi
                            
                            last_progress=$current_progress
                        elif [ "$current_size" -gt 0 ]; then
                            # Show size-based progress with download rate
                            local progress_percent=$((current_size * 100 / target_buffer_size))
                            if [ $progress_percent -gt 100 ]; then
                                progress_percent=100
                            fi
                            
                            local width=20
                            local filled=$((progress_percent * width / 100))
                            if [ "$filled" -gt "$width" ]; then
                                filled=$width
                            fi
                            
                            local bar=""
                            local i=0
                            while [ $i -lt $filled ]; do
                                bar="${bar}🟩"
                                i=$((i + 1))
                            done
                            while [ $i -lt $width ]; do
                                bar="${bar}⬜"
                                i=$((i + 1))
                            done
                            
                            # Build size-based display
                            local size_display_full="${size_display} / $((target_buffer_size / 1048576)) MB"
                            if [ -n "$speed_display" ] && [ "$bytes_per_sec" -gt 0 ]; then
                                size_display_full="${size_display_full} @ ~$speed_display"
                            fi
                            if [ "$total_peers" -gt 0 ]; then
                                size_display_full="${size_display_full} | ${connected_peers}/${total_peers} peers"
                            fi
                            
                            printf "\r${CYAN}Buffering:${RESET} %s %d%% (%s)" "$bar" "$progress_percent" "$size_display_full"
                            
                            # Check if we have enough buffer
                            if [ "$current_size" -ge $target_buffer_size ]; then
                                echo ""
                                echo -e "${GREEN}✓ Buffer ready (${size_display} downloaded)${RESET}"
                                break
                            fi
                            
                            # Check if stalled but have minimum buffer
                            if [ "$current_size" -eq "$last_size" ] && [ "$current_size" -gt 0 ]; then
                                if [ "$current_size" -ge 20971520 ]; then  # 20MB minimum
                                    echo ""
                                    echo -e "${YELLOW}⚠ Proceeding with available buffer (${size_display})${RESET}"
                                    break
                                fi
                            fi
                        else
                            # Show initial state with peer info if available
                            local initial_display="Connecting..."
                            if [ "$total_peers" -gt 0 ]; then
                                initial_display="${initial_display} (${connected_peers}/${total_peers} peers)"
                            fi
                            printf "\r${CYAN}Buffering:${RESET} ⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜ 0%% - $initial_display"
                        fi
                        
                        # Update tracking variables
                        if [ "$current_size" != "$last_size" ] || [ "$current_progress" != "$last_progress" ]; then
                            last_update_time=$current_time
                        fi
                        last_size=$current_size
                        sleep 0.5  # Update more frequently (every 0.5 seconds)
                        buffer_wait=$((buffer_wait + 1))
                    done
                    echo ""
                    
                    # Find subtitle file (same logic as peerflix)
                    local subtitle_file=""
                    local subtitle_arg=""
                    
                    if [ "$enable_subtitles" = true ] || has_subtitles "$source" >/dev/null 2>&1; then
                        echo -e "${CYAN}Searching for subtitle file...${RESET}"
                        
                        # Search for subtitle files in the same directory as video
                        subtitle_file=$(find "$video_dir" -type f \( -iname "*.srt" -o -iname "*.vtt" -o -iname "*.ass" -o -iname "*.ssa" \) 2>/dev/null | head -1)
                        
                        if [ -n "$subtitle_file" ] && [ -f "$subtitle_file" ]; then
                            local sub_abs=$(realpath "$subtitle_file" 2>/dev/null || echo "$subtitle_file")
                            local sub_name=$(basename "$sub_abs")
                            local sub_dir=$(dirname "$sub_abs")
                            
                            echo -e "${GREEN}✓ Subtitle found:${RESET} $sub_name"
                            
                            if [ "$sub_dir" = "$video_dir" ]; then
                                subtitle_arg="$sub_name"
                            else
                                subtitle_arg="$sub_abs"
                            fi
                        fi
                    fi
                    
                    # Launch player (same as peerflix)
                    echo ""
                    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                    echo -e "${GREEN}Launching $player from local directory...${RESET}"
                    echo -e "  ${CYAN}Directory:${RESET} $video_dir"
                    echo -e "  ${CYAN}Video:${RESET} $video_name"
                    if [ -n "$subtitle_arg" ]; then
                        echo -e "  ${CYAN}Subtitle:${RESET} $subtitle_arg"
                    fi
                    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                    echo ""
                    
                    local player_pid=""
                    cd "$video_dir" || {
                        echo -e "${RED}Error:${RESET} Could not change to video directory"
                        kill $transmission_pid 2>/dev/null || true
                        # Restore original transmission config if we modified it
                        if [ -n "$config_backup" ] && [ -f "$config_backup" ]; then
                            cp "$config_backup" "$transmission_config" 2>/dev/null
                            rm -f "$config_backup" 2>/dev/null
                        fi
                        rm -f "$transmission_output" 2>/dev/null
                        rm -f "$temp_output" 2>/dev/null
                        return 1
                    }
                    
                    if [ -z "$player" ]; then
                         player=$(get_active_player)
                    fi
                    
                    
                    # Check if we have a splash screen MPV to transition
                    if [[ -n "${TERMFLIX_SPLASH_SOCKET:-}" ]] && [[ -S "$TERMFLIX_SPLASH_SOCKET" ]]; then
                        # Use existing MPV splash screen - transition to video
                        echo -e "${GREEN}Transitioning splash screen to video...${RESET}"
                        mpv_transition_to_video "$TERMFLIX_SPLASH_SOCKET" "$video_name" "$subtitle_arg"
                        # Find MPV PID from socket
                        player_pid=$(lsof -t "$TERMFLIX_SPLASH_SOCKET" 2>/dev/null | head -1)
                        if [[ -z "$player_pid" ]] || ! kill -0 "$player_pid" 2>/dev/null; then
                            echo -e "${RED}Error:${RESET} Could not find MPV process after transition"
                            rm -f "$transmission_output" 2>/dev/null
                            rm -f "$temp_output" 2>/dev/null
                            return 1
                        fi
                    else
                        # No splash screen - launch new player as normal
                        player_pid=$(launch_player "$video_name" "$subtitle_arg" "$movie_title")
                        
                        if [ -z "$player_pid" ] || ! kill -0 "$player_pid" 2>/dev/null; then
                            echo -e "${RED}Error:${RESET} Failed to launch player"
                            rm -f "$transmission_output" 2>/dev/null
                            rm -f "$temp_output" 2>/dev/null
                            return 1
                        fi
                    fi
                    
                    echo -e "${CYAN}Player started (PID: $player_pid). Transmission running (PID: $transmission_pid)${RESET}"
                    echo ""
                    
                    # Monitor player (same as peerflix)
                    local player_running=true
                    local check_count=0
                    
                    trap 'echo -e "\n${YELLOW}Interrupted. Stopping transmission...${RESET}"; kill $transmission_pid 2>/dev/null || true; kill $player_pid 2>/dev/null || true; if [ -n "$config_backup" ] && [ -f "$config_backup" ]; then cp "$config_backup" "$transmission_config" 2>/dev/null; rm -f "$config_backup" 2>/dev/null; fi; rm -f "$transmission_output" 2>/dev/null; return 2' INT TERM

                    # Generic PID-based monitoring (works for mpv, vlc, iina, etc.)
                    while kill -0 "$player_pid" 2>/dev/null; do
                        sleep 1
                        check_count=$((check_count + 1))
                        
                        # 4 hour timeout to prevent zombie loops
                        if [ $check_count -gt 14400 ]; then
                            echo -e "${YELLOW}Warning:${RESET} Max play time reached, stopping monitoring"
                            break
                        fi
                    done
                    
                    player_running=false
                    
                    trap - INT TERM
                    
                    # Player closed, stop transmission
                    echo -e "${CYAN}Player closed. Stopping transmission...${RESET}"
                    kill $transmission_pid 2>/dev/null || true
                    sleep 1
                    kill -9 $transmission_pid 2>/dev/null || true
                    wait $transmission_pid 2>/dev/null &>/dev/null || true
                    
                    # Restore original transmission config if we modified it
                    if [ -n "$config_backup" ] && [ -f "$config_backup" ]; then
                        cp "$config_backup" "$transmission_config" 2>/dev/null
                        rm -f "$config_backup" 2>/dev/null
                        echo -e "${CYAN}Restored transmission config${RESET}"
                    fi
                    
                    rm -f "$transmission_output" 2>/dev/null
                    rm -f "$temp_output" 2>/dev/null
                    return 2  # Return to catalog
                else
                    # transmission-cli not available, show error and exit
                    echo -e "${RED}Error:${RESET} peerflix failed and transmission-cli is not installed"
                    echo ""
                    echo "Please install transmission-cli:"
                    echo "  ${GREEN}brew install transmission-cli${RESET}"
                    rm -f "$temp_output" 2>/dev/null
                    return 1
                fi
                
                echo -e "${CYAN}Solutions:${RESET}"
                echo "  1. Try selecting a different torrent from the list"
                if ! command -v transmission-cli &> /dev/null; then
                    echo "  2. Install transmission-cli for download fallback:"
                    echo "     ${GREEN}brew install transmission-cli${RESET}"
                    echo "     Then use: ${GREEN}transmission-cli --download-dir \"/tmp/torrent-stream\" \"$source\"${RESET}"
                fi
                echo "  3. Use webtorrent (if installed):"
                echo "     ${GREEN}webtorrent \"$source\" --mpv${RESET}"
                echo "  4. Or add to transmission-daemon:"
                echo "     ${GREEN}transmission-remote -a \"$source\"${RESET}"
                echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                rm -f "$temp_output" 2>/dev/null
                return 1
            fi
        fi
    fi
    
    # Wait for peerflix to start and show the path
    sleep 4
    
    # Extract the torrent path from peerflix output
    local torrent_path=""
        local max_wait=125 # 25 seconds * 5
        local waited=0
    
        echo -e "${CYAN}Waiting for peerflix to show torrent path...${RESET}"
        while [ $waited -lt $max_wait ]; do
            if [ -f "$temp_output" ] && [ -s "$temp_output" ]; then
                # Read the file content (handle potential buffering)
                local output_content=$(cat "$temp_output" 2>/dev/null)
                
                # Try multiple patterns to find the path - "info path" followed by path
                # Pattern: "info path /tmp/torrent-stream/..."
                torrent_path=$(echo "$output_content" | grep "info path" 2>/dev/null | head -1 | sed -E 's/.*info path[[:space:]]+//' | awk '{print $1}' | tr -d '\r\n')
                
                # If not found, try extracting from "info path" line more carefully
                if [ -z "$torrent_path" ]; then
                    torrent_path=$(echo "$output_content" | grep "info path" 2>/dev/null | head -1 | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/[[:space:]]*$//' | awk '{print $1}')
                fi
                
                # Try finding torrent-stream path (generic)
                if [ -z "$torrent_path" ]; then
                    torrent_path=$(echo "$output_content" | grep -oE "(/[a-zA-Z0-9_.-]+)+/torrent-stream/[a-zA-Z0-9]+" | head -1)
                fi
                
                # Try finding any path after "info path" (generic)
                if [ -z "$torrent_path" ]; then
                    torrent_path=$(echo "$output_content" | grep "info path" 2>/dev/null | grep -oE "(/[a-zA-Z0-9_.-]+)+" | grep -v "info path" | head -1)
                fi
                
                # Verify it's a directory
                if [ -n "$torrent_path" ] && [ -d "$torrent_path" ]; then
                    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                    echo -e "${GREEN}✓ TORRENT PATH:${RESET}"
                    echo -e "${CYAN}$torrent_path${RESET}"
                    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                    break
                fi
            fi
            # Charm-style dual spinner
            local charm_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
            local charm_len=${#charm_chars[@]}
            local idx1=$(( (charm_len - (waited % charm_len)) % charm_len ))
            local idx2=$(( waited % charm_len ))
            printf "\r${MAGENTA}${charm_chars[$idx1]}${CYAN}${charm_chars[$idx2]}${RESET} Waiting for torrent path..."
            
            sleep 0.2
            waited=$((waited + 1))
            if [ $((waited % 15)) -eq 0 ]; then
                printf "\r${YELLOW}Still waiting... ($((waited / 5))s)${RESET}    \n"
                # Show what we've found so far for debugging
                if [ -f "$temp_output" ] && [ -s "$temp_output" ]; then
                    local found_line=$(grep "info path" "$temp_output" 2>/dev/null | head -1)
                    if [ -n "$found_line" ]; then
                        echo -e "${CYAN}Found 'info path' line:${RESET} $found_line"
                        # Try to extract path from this line
                        local test_path=$(echo "$found_line" | sed -E 's/.*info path[[:space:]]+//' | awk '{print $1}')
                        if [ -n "$test_path" ]; then
                            echo -e "${CYAN}Extracted path:${RESET} $test_path"
                            if [ -d "$test_path" ]; then
                                echo -e "${GREEN}Path exists and is a directory!${RESET}"
                                torrent_path="$test_path"
                                break
                            else
                                echo -e "${YELLOW}Path does not exist yet or is not a directory${RESET}"
                            fi
                        fi
                    fi
                fi
            fi
        done
    
    # If still not found, show debug output
    if [ -z "$torrent_path" ] || [ ! -d "$torrent_path" ]; then
        echo -e "${RED}Error:${RESET} Could not determine torrent path"
        echo -e "${YELLOW}Peerflix output for debugging:${RESET}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        if [ -f "$temp_output" ]; then
            cat "$temp_output" 2>/dev/null | tail -30
        else
            echo "  (no output file found)"
        fi
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        kill $peerflix_pid 2>/dev/null || true
        rm -f "$temp_output" 2>/dev/null
        return 1
    fi
    
    # Wait for video file to be available (search recursively)
    # Give peerflix time to start downloading files first
    echo -e "${CYAN}Waiting for files to download...${RESET}"
    sleep 3  # Give peerflix time to create directory structure and start downloading
    
    echo -e "${CYAN}Searching for video file...${RESET}"
    local video_file=""
    local video_wait=0
    local max_video_wait=150  # 30 seconds * 5
    
    while [ $video_wait -lt $max_video_wait ]; do
        # First, check if directory exists and has any files at all
        if [ ! -d "$torrent_path" ]; then
            sleep 0.2
            video_wait=$((video_wait + 1))
            continue
        fi
        
        # List all files first to see what we have
        local all_files=$(find "$torrent_path" -type f 2>/dev/null)
        if [ -z "$all_files" ]; then
            # No files yet, wait longer
            # Charm-style dual spinner
            local charm_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
            local charm_len=${#charm_chars[@]}
            local idx1=$(( (charm_len - (video_wait % charm_len)) % charm_len ))
            local idx2=$(( video_wait % charm_len ))
            local wait_secs=$((video_wait / 5))
            printf "\r${MAGENTA}${charm_chars[$idx1]}${CYAN}${charm_chars[$idx2]}${RESET} Waiting for files to download... ${PURPLE}[${CYAN}%ds${PURPLE}]${RESET}" "$wait_secs"
            sleep 0.2
            video_wait=$((video_wait + 1))
            continue
        fi
        
        # Debug: show what files we found
        if [ "$TORRENT_DEBUG" = true ] && [ $((video_wait % 25)) -eq 0 ]; then
            echo ""
            echo -e "${CYAN}Files found so far:${RESET}"
            echo "$all_files" | head -5 | while IFS= read -r file; do
                if [ -n "$file" ]; then
                    local rel_path="${file#$torrent_path/}"
                    local fsize=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
                    echo -e "  ${CYAN}→${RESET} $rel_path (${fsize} bytes)"
                fi
            done
            echo ""
        fi
        
        # Find the largest video file recursively (usually the main movie file)
        # Use find to get all video files, then sort by size
        video_file=$(find "$torrent_path" -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.m4v" -o -iname "*.flv" -o -iname "*.wmv" \) 2>/dev/null | \
            while IFS= read -r file; do
                if [ -f "$file" ] && [ -s "$file" ]; then
                    local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
                    echo "$size|$file"
                fi
            done | sort -t'|' -k1 -rn | head -1 | cut -d'|' -f2)
        
        if [ -n "$video_file" ] && [ -f "$video_file" ] && [ -s "$video_file" ]; then
            # Check if file is large enough (at least 1MB) to be a real video
            local file_size=$(stat -f%z "$video_file" 2>/dev/null || stat -c%s "$video_file" 2>/dev/null || echo "0")
            if [ "$file_size" -gt 1048576 ]; then  # 1MB
                printf "\r${GREEN}✓ Video file found${RESET}\n"
                break
            fi
        fi
        
        # Charm-style dual spinner
        local charm_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
        local charm_len=${#charm_chars[@]}
        local idx1=$(( (charm_len - (video_wait % charm_len)) % charm_len ))
        local idx2=$(( video_wait % charm_len ))
        local search_secs=$((video_wait / 5))
        printf "\r${MAGENTA}${charm_chars[$idx1]}${CYAN}${charm_chars[$idx2]}${RESET} Searching for video file... ${PURPLE}[${CYAN}%ds${PURPLE}]${RESET}" "$search_secs"
        
        sleep 0.2
        video_wait=$((video_wait + 1))
    done
    
    if [ -z "$video_file" ] || [ ! -f "$video_file" ]; then
        echo ""
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${RED}Error:${RESET} Could not find video file in torrent"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${YELLOW}Torrent path:${RESET} $torrent_path"
        echo ""
        echo -e "${YELLOW}Directory structure:${RESET}"
        ls -la "$torrent_path" 2>/dev/null | head -20 || echo "  (directory listing failed)"
        echo ""
        echo -e "${YELLOW}All files found (recursive):${RESET}"
        local found_any=false
        find "$torrent_path" -type f 2>/dev/null | while IFS= read -r file; do
            if [ -n "$file" ]; then
                found_any=true
                local rel_path="${file#$torrent_path/}"
                local fsize=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
                local fname=$(basename "$file")
                echo -e "  ${CYAN}→${RESET} $rel_path"
                echo -e "    ${YELLOW}Size:${RESET} ${fsize} bytes | ${YELLOW}Name:${RESET} $fname"
            fi
        done
        if [ "$found_any" = false ]; then
            echo -e "  ${YELLOW}(no files found - torrent may still be downloading)${RESET}"
            echo ""
            echo -e "${CYAN}Note:${RESET} This torrent may not have any video files, or files are still downloading."
            echo -e "${CYAN}Try:${RESET} Wait a moment and try again, or check the torrent contents manually."
        fi
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        kill $peerflix_pid 2>/dev/null || true
        rm -f "$temp_output" 2>/dev/null
        return 1
    fi
    
    local video_path=$(realpath "$video_file" 2>/dev/null || echo "$video_file")
    local video_dir=$(dirname "$video_path")
    local video_name=$(basename "$video_path")
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${GREEN}✓ Video file found:${RESET} $video_name"
    echo -e "${CYAN}Video directory:${RESET} $video_dir"
    echo -e "${CYAN}Full path:${RESET} $video_path"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
    
    # Buffer video before starting player (wait for 3-4 minutes of content)
    # Smart buffering: Download initial chunk to analyze video
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${CYAN}Buffering video...${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    # Phase 1: Download 2MB for analysis
    local analysis_size=2097152  # 2MB
    local target_buffer_size=0
    local buffer_calculated=false
    local buffer_wait=0
    local max_buffer_wait=300  # 5 minutes max wait
    local last_size=0
    local stalled_count=0
    local connected_peers=0
    total_peers=0
    
    while [ $buffer_wait -lt $max_buffer_wait ]; do
        if [ ! -f "$video_path" ]; then
            sleep 1
            buffer_wait=$((buffer_wait + 1))
            continue
        fi
        
        local current_size=$(stat -f%z "$video_path" 2>/dev/null || stat -c%s "$video_path" 2>/dev/null || echo "0")
        
        # Phase 1: Analyze video after 2MB downloaded
        if [ "$buffer_calculated" = false ] && [ "$current_size" -ge "$analysis_size" ]; then
            echo ""
            echo -e "${YELLOW}Analyzing video bitrate...${RESET}"
            
            # Calculate download speed so far
            local download_speed=0
            if [ $buffer_wait -gt 0 ]; then
                download_speed=$((current_size / buffer_wait))
            fi
            
            # Calculate optimal buffer
            target_buffer_size=$(calculate_optimal_buffer "$video_path" "$download_speed")
            buffer_calculated=true
            
            # Convert to MB for display
            local buffer_mb=$((target_buffer_size / 1048576))
            echo -e "${GREEN}✓ Buffer target: ${buffer_mb} MB${RESET}"
            echo ""
            
            # Write analysis status
            if [ -n "$TERMFLIX_BUFFER_STATUS" ]; then
                local progress_percent=$((current_size * 100 / analysis_size))
                [ $progress_percent -gt 100 ] && progress_percent=100
                local speed_bytes=$download_speed
                local size_mb=$((current_size / 1048576))
                echo "${progress_percent}|${speed_bytes}|${connected_peers}|${total_peers}|${size_mb}|ANALYZING" > "$TERMFLIX_BUFFER_STATUS"
            fi
        fi
        
        # Skip rest if we haven't calculated buffer yet
        if [ "$buffer_calculated" = false ]; then
            sleep 1
            buffer_wait=$((buffer_wait + 1))
            
            # Write initial analyzing status
            if [ -n "$TERMFLIX_BUFFER_STATUS" ]; then
                local progress_percent=$((current_size * 100 / analysis_size))
                [ $progress_percent -gt 100 ] && progress_percent=100
                local size_mb=$((current_size / 1048576))
                echo "${progress_percent}|0|0|0|${size_mb}|ANALYZING" > "$TERMFLIX_BUFFER_STATUS"
            fi
            continue
        fi
        
        # Extract peer information from peerflix output
        if [ -f "$temp_output" ] && [ -s "$temp_output" ]; then
            local peer_info=$(grep "info streaming" "$temp_output" 2>/dev/null | tail -1)
            if [ -n "$peer_info" ]; then
                # Extract "from X/Y peers" pattern: "info streaming ... from 5/10 peers"
                # Pattern can be: "from 5/10 peers" or "from 5/10"
                local peer_match=$(echo "$peer_info" | grep -oE "from [0-9]+/[0-9]+" 2>/dev/null | head -1)
                if [ -n "$peer_match" ]; then
                    # Extract connected peers (first number)
                    connected_peers=$(echo "$peer_match" | sed -E 's/from ([0-9]+)\/[0-9]+/\1/' 2>/dev/null)
                    # Extract total peers (second number)
                    total_peers=$(echo "$peer_match" | sed -E 's/from [0-9]+\/([0-9]+)/\1/' 2>/dev/null)
                fi
            fi
        fi
        
        # Check if file is growing (not stalled)
        if [ "$current_size" -eq "$last_size" ] && [ "$current_size" -gt 0 ]; then
            stalled_count=$((stalled_count + 1))
            if [ $stalled_count -gt 10 ]; then
                # File hasn't grown in 10 seconds, might be stalled or complete
                # If we have enough buffer, proceed anyway
                if [ "$current_size" -ge $target_buffer_size ]; then
                    break
                fi
            fi
        else
            stalled_count=0
        fi
        
        last_size=$current_size
        
        # Show progress with peer information
        if [ "$current_size" -gt 0 ]; then
            # Calculate progress as percentage of target buffer
            local progress_percent=$((current_size * 100 / target_buffer_size))
            if [ $progress_percent -gt 100 ]; then
                progress_percent=100
            fi
            
            # Build progress bar
            local width=20
            local filled=$((progress_percent * width / 100))
            if [ "$filled" -gt "$width" ]; then
                filled=$width
            fi
            
            local bar=""
            local i=0
            while [ $i -lt $filled ]; do
                bar="${bar}🟩"
                i=$((i + 1))
            done
            while [ $i -lt $width ]; do
                bar="${bar}⬜"
                i=$((i + 1))
            done
            
            # Calculate download speed (bytes per second)
            local bytes_per_sec=0
            if [ $buffer_wait -gt 0 ]; then
                bytes_per_sec=$((current_size / buffer_wait))
            fi
            
            # Convert size to MB
            local size_mb=$((current_size / 1048576))
            
            # Write status to file for inline buffering UI
            if [ -n "$TERMFLIX_BUFFER_STATUS" ]; then
                echo "${progress_percent}|${bytes_per_sec}|${connected_peers}|${total_peers}|${size_mb}|BUFFERING" > "$TERMFLIX_BUFFER_STATUS"
            fi
            
            # Show peers if available, otherwise show percentage
            if [ "$total_peers" -gt 0 ]; then
                printf "\r${CYAN}Buffering:${RESET} %s %d%% (%d/%d peers) " "$bar" "$progress_percent" "$connected_peers" "$total_peers"
            else
                printf "\r${CYAN}Buffering:${RESET} %s %d%% " "$bar" "$progress_percent"
            fi
        else
            # Write initial status
            if [ -n "$TERMFLIX_BUFFER_STATUS" ]; then
                echo "0|0|${connected_peers}|${total_peers}|0|BUFFERING" > "$TERMFLIX_BUFFER_STATUS"
            fi
            
            if [ "$total_peers" -gt 0 ]; then
                printf "\r${CYAN}Buffering...${RESET} [0%%] (%d/%d peers) " "$connected_peers" "$total_peers"
            else
                printf "\r${CYAN}Buffering...${RESET} [0%%]"
            fi
        fi
        
        # If we have enough buffer, proceed
        if [ "$current_size" -ge $target_buffer_size ]; then
            echo ""  # New line after progress bar
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
            echo -e "${GREEN}✓ Buffer ready (${current_size} bytes)${RESET}"
            if [ "$total_peers" -gt 0 ]; then
                echo -e "${CYAN}Connected to ${connected_peers}/${total_peers} peers${RESET}"
            fi
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
            
            # Write READY status with final metrics
            if [ -n "$TERMFLIX_BUFFER_STATUS" ]; then
                local final_percent=100
                local size_mb=$((current_size / 1048576))
                local bytes_per_sec=0
                if [ $buffer_wait -gt 0 ]; then
                    bytes_per_sec=$((current_size / buffer_wait))
                fi
                echo "${final_percent}|${bytes_per_sec}|${connected_peers}|${total_peers}|${size_mb}|READY" > "$TERMFLIX_BUFFER_STATUS"
            fi
            
            break
        fi
        
        sleep 1
        buffer_wait=$((buffer_wait + 1))
    done
    
    # Final check
    local final_size=$(stat -f%z "$video_path" 2>/dev/null || stat -c%s "$video_path" 2>/dev/null || echo "0")
    if [ "$final_size" -lt $target_buffer_size ]; then
        echo ""  # New line after progress bar
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${YELLOW}⚠ Warning:${RESET} Buffer not fully ready (${final_size} bytes), but proceeding..."
        if [ "$total_peers" -gt 0 ]; then
            echo -e "${CYAN}Connected to ${connected_peers}/${total_peers} peers${RESET}"
        fi
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        
        # Write READY status even though buffer isn't full (player is starting)
        if [ -n "$TERMFLIX_BUFFER_STATUS" ]; then
            local final_percent=$((final_size * 100 / target_buffer_size))
            [ $final_percent -gt 100 ] && final_percent=100
            local size_mb=$((final_size / 1048576))
            local bytes_per_sec=0
            if [ $buffer_wait -gt 0 ]; then
                bytes_per_sec=$((final_size / buffer_wait))
            fi
            echo "${final_percent}|${bytes_per_sec}|${connected_peers}|${total_peers}|${size_mb}|READY" > "$TERMFLIX_BUFFER_STATUS"
        fi
    fi
    echo
    
    # Prepare subtitle file path (relative to video file directory)
    local subtitle_arg=""
    if [ -n "$subtitle_file" ] && [ -f "$subtitle_file" ]; then
        local sub_abs=$(realpath "$subtitle_file" 2>/dev/null || echo "$subtitle_file")
        local sub_name=$(basename "$sub_abs")
        local sub_dir=$(dirname "$sub_abs")
        
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${GREEN}✓ SRT File Found:${RESET} $sub_abs"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo
        
        # Check if subtitle is in the same directory as video
        if [ "$sub_dir" = "$video_dir" ]; then
            # Same directory - use relative path (just filename)
            subtitle_arg="$sub_name"
        else
            # Different directory - use absolute path
            subtitle_arg="$sub_abs"
        fi
    fi
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${GREEN}Launching $player with peerflix stream...${RESET}"
    echo -e "  ${CYAN}Stream URL:${RESET} http://localhost:8888/"
    if [ -n "$subtitle_arg" ]; then
        echo -e "  ${CYAN}Subtitle:${RESET} $subtitle_arg (from $video_dir)"
    fi
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
    
    # Launch player with HTTP stream URL (allows seeking ahead)
    local player_pid=""
    local stream_url="http://localhost:8888/"
    
    # Check if we have a splash screen MPV to transition
    if [[ -n "${TERMFLIX_SPLASH_SOCKET:-}" ]] && [[ -S "$TERMFLIX_SPLASH_SOCKET" ]]; then
        # Use existing MPV splash screen - transition to video
        echo -e "${GREEN}Transitioning splash screen to video...${RESET}"
        mpv_transition_to_video "$TERMFLIX_SPLASH_SOCKET" "$stream_url" ""
        # Find MPV PID from socket
        player_pid=$(lsof -t "$TERMFLIX_SPLASH_SOCKET" 2>/dev/null | head -1)
        if [[ -z "$player_pid" ]] || ! kill -0 "$player_pid" 2>/dev/null; then
            echo -e "${RED}Error:${RESET} Could not find MPV process after transition"
            return 1
        fi
        echo -e "${CYAN}Transitioned to video (PID: $player_pid)${RESET}"
    else
        # No splash screen - launch new player as normal
    
    if [ "$player" = "vlc" ]; then
        if [ -n "$subtitle_arg" ]; then
            local sub_path="$video_dir/$subtitle_arg"
            echo -e "${YELLOW}Command:${RESET} vlc \"$stream_url\" --sub-file=\"$sub_path\""
            vlc "$stream_url" --sub-file="$sub_path" > /dev/null 2>&1 &
            player_pid=$!
        else
            vlc "$stream_url" > /dev/null 2>&1 &
            player_pid=$!
        fi
    else
        # mpv - use HTTP URL for better seeking
        # Build window title with movie name if available
        local window_title="TermFlix™"
        if [ -n "$movie_title" ]; then
            window_title="TermFlix™ - $movie_title"
        fi
        
        # HTTP streaming with aggressive caching for continuous buffering
        local mpv_args=(
            "--title=$window_title"
            "--cache=yes"              # Enable cache
            "--cache-secs=300"         # 5 minutes cache (continuous buffering)
            "--demuxer-max-bytes=512M" # 512MB demuxer buffer
            "--demuxer-max-back-bytes=256M" # 256MB backward buffer for seeking
            "$stream_url"
        )
        if [ -n "$subtitle_arg" ]; then
            local sub_path="$video_dir/$subtitle_arg"
            echo -e "${YELLOW}Command:${RESET} mpv \"$stream_url\" --sub-file=\"$sub_path\" --sid=1 --sub-visibility=yes"
            mpv_args+=("--sub-file=$sub_path")
            mpv_args+=("--sid=1")
            mpv_args+=("--sub-visibility=yes")
        fi
        
        # Use TMPDIR for logs
        local mpv_log="${TMPDIR:-/tmp}/termflix_mpv_debug.log"
        echo -e "DEBUG: Launching mpv to log: $mpv_log"
        mpv "${mpv_args[@]}" >> "$mpv_log" 2>&1 &
        player_pid=$!
    fi
    fi  # End of splash check
    
    if [ -z "$player_pid" ] || ! kill -0 "$player_pid" 2>/dev/null; then
        echo -e "${RED}Error:${RESET} Failed to launch player"
        kill $peerflix_pid 2>/dev/null || true
        rm -f "$temp_output" 2>/dev/null
        return 1
    fi
    
    echo -e "${CYAN}Player started (PID: $player_pid). Peerflix running (PID: $peerflix_pid)${RESET}"
    echo ""
    
    # Monitor player - when it exits, clean up peerflix
    trap 'echo -e "\n${YELLOW}Interrupted. Stopping peerflix...${RESET}"; kill $peerflix_pid 2>/dev/null || true; return 130' INT TERM
    
    # Wait for player to finish
    wait "$player_pid" 2>/dev/null
    local player_exit=$?
    
    # Player finished - cleanup peerflix
    echo -e "${CYAN}Playback finished. Cleaning up...${RESET}"
    kill "$peerflix_pid" 2>/dev/null || true
    wait "$peerflix_pid" 2>/dev/null || true
    
    # Return 0 to indicate successful stream (catalog will loop)
    return 0
    
    # Note: Player monitoring logic extracted to bin/modules/streaming/player.sh
    # Function monitor_player_process() handles VLC/mpv fork detection and cleanup
    # Removed during Dec 2025 refactoring to reduce torrent.sh size
}



# Main streaming function
stream_torrent() {
    local source="$1"
    local index="${2:-}"
    local list_only="${3:-false}"
    local enable_subtitles="${4:-false}"
    local movie_title="${5:-Termflix Stream}"
    
    # Validate source (must be magnet link or file path)
    if [ -z "$source" ]; then
        echo -e "${RED}Error:${RESET} No torrent source provided"
        return 1
    fi
    
    # Clean up source (remove whitespace, newlines)
    source=$(echo "$source" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Check if it's a magnet link or file path
    if [[ ! "$source" =~ ^magnet: ]] && [ ! -f "$source" ]; then
        echo -e "${RED}Error:${RESET} Invalid torrent source: '$source'"
        echo -e "${YELLOW}Expected:${RESET} magnet link (magnet:?xt=...) or path to .torrent file"
        return 1
    fi
    
    # Ensure TORRENT_TOOL is set (should always be peerflix now)
    if [ -z "$TORRENT_TOOL" ]; then
        check_deps
    fi
    
    # Only use peerflix
    if [ "$list_only" = true ]; then
        peerflix "$source" --list
    else
        stream_peerflix "$source" "$index" "$enable_subtitles" "$movie_title"
    fi
}

# Auto-select best quality
select_best_quality() {
    local source="$1"
    
    echo -e "${YELLOW}Analyzing available files...${RESET}"
    
    # List files and find the largest video file
    # Use peerflix to list files
    local file_list=$(peerflix "$source" --list 2>/dev/null || echo "")
    
    if [ -z "$file_list" ]; then
        echo -e "${YELLOW}Could not list files, playing default...${RESET}"
        return 0
    fi
    
    # Find video files and select the largest one
    local best_file=$(echo "$file_list" | grep -iE '\.(mp4|mkv|avi|mov|webm|m4v)' | \
        awk '{print $1, $2}' | sort -k2 -rn | head -1 | awk '{print $1}')
    
    if [ -n "$best_file" ]; then
        echo -e "${GREEN}Selected best quality file (index $best_file)${RESET}"
        echo "$best_file"
    else
        echo -e "${YELLOW}No video files found, using default...${RESET}"
        echo "0"
    fi
}
