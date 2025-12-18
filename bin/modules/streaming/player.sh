#!/usr/bin/env bash
#
# Termflix Player Module
# Handles video player detection, launching, and process monitoring
#

# Source dependencies
source "${BASH_SOURCE%/*}/../core/colors.sh"
source "${BASH_SOURCE%/*}/../core/logging.sh"

# Detect available players in system
detect_players() {
    local players=()
    
    if command -v mpv &> /dev/null; then
        players+=("mpv")
    fi
    
    # Check for IINA on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if [ -d "/Applications/IINA.app" ] || command -v iina &> /dev/null; then
            players+=("iina")
        fi
    fi
    
    if command -v vlc &> /dev/null || [ -d "/Applications/VLC.app" ]; then
        players+=("vlc")
    fi
    
    if command -v mplayer &> /dev/null; then
        players+=("mplayer")
    fi
    
    echo "${players[@]}"
}

# Get preferred player (with auto-detection fallback)
get_active_player() {
    local configured_player=$(get_player_preference 2>/dev/null)
    
    if [ -n "$configured_player" ] && [ "$configured_player" != "auto" ]; then
        echo "$configured_player"
        return 0
    fi
    
    # Auto-detect priority: mpv > iina > vlc > mplayer
    local available_players=($(detect_players))
    
    if [ ${#available_players[@]} -eq 0 ]; then
        log_error "No video players found! Please install mpv, vlc, or iina."
        return 1
    fi
    
    echo "${available_players[0]}"
}


# Launch MPV splash screen with backdrop image and title
# Args: $1 = backdrop/poster image path, $2 = movie title
# Returns: "PID|SOCKET_PATH" (pipe-separated)
launch_splash_screen() {
    local image_path="$1"
    local movie_title="${2:-TermFlix™}"
    
    [[ "$TORRENT_DEBUG" == "true" ]] && echo "DEBUG [launch_splash_screen]: Called with image=$image_path, title=$movie_title" >&2
    
    if [[ ! -f "$image_path" ]]; then
        [[ "$TORRENT_DEBUG" == "true" ]] && echo "DEBUG [launch_splash_screen]: Image file not found!" >&2
        log_error "Splash image not found: $image_path"
        return 1
    fi
    
    [[ "$TORRENT_DEBUG" == "true" ]] && echo "DEBUG [launch_splash_screen]: Image file exists" >&2
    
    # Create IPC socket for MPV control
    local ipc_socket="${TMPDIR:-/tmp}/termflix_mpv_splash_$$.sock"
    [[ "$TORRENT_DEBUG" == "true" ]] && echo "DEBUG [launch_splash_screen]: IPC socket will be: $ipc_socket" >&2
    
    # MPV args for splash screen with IPC
    local mpv_args=(
        "--input-ipc-server=$ipc_socket"  # Enable IPC for loadfile command
        "--image-display-duration=inf"  # Keep showing indefinitely
        "--title=TermFlix™ - $movie_title"
        "--force-media-title=$movie_title"
        "--osd-level=3"  # Show all OSD messages
        "--osd-msg1=Buffering..."  # Initial message
        "--osd-font-size=48"
        "--osd-color=#00FF00"
        "--osd-border-size=2"
        "--keep-open=yes"  # Don't close when image ends
        "--fullscreen"  # Display fullscreen
        "--panscan=1.0"  # Zoom to fill screen
        # Pre-configure cache for video transition (essential for seamless playback)
        "--cache=yes"
        "--cache-secs=300"           # 5 minutes
        "--demuxer-max-bytes=512M"   # 512MB
        "--demuxer-max-back-bytes=256M" 
        "$image_path"
    )
    
    local mpv_error_log="${TMPDIR:-/tmp}/termflix_mpv_splash_error.log"
    mpv "${mpv_args[@]}" >"$mpv_error_log" 2>&1 &
    local splash_pid=$!
    [[ "$TORRENT_DEBUG" == "true" ]] && echo "DEBUG [launch_splash_screen]: MPV PID=$splash_pid, errors in: $mpv_error_log" >&2
    
    # Wait for socket to be created (up to 2 seconds)
    local wait_count=0
    while [[ ! -S "$ipc_socket" ]] && [[ $wait_count -lt 20 ]]; do
        sleep 0.1
        ((wait_count++))
    done
    

    
    if [[ "$TORRENT_DEBUG" == "true" ]]; then
        echo "DEBUG [launch_splash_screen]: Waited ${wait_count}x100ms for socket" >&2
        echo "DEBUG [launch_splash_screen]: Socket exists: $(test -S "$ipc_socket" && echo YES || echo NO)" >&2
        echo "DEBUG [launch_splash_screen]: Process alive: $(kill -0 "$splash_pid" 2>/dev/null && echo YES || echo NO)" >&2
    fi
    
    if kill -0 "$splash_pid" 2>/dev/null && [[ -S "$ipc_socket" ]]; then
        local result="${splash_pid}|${ipc_socket}"
        [[ "$TORRENT_DEBUG" == "true" ]] && echo "DEBUG [launch_splash_screen]: SUCCESS! Returning: $result" >&2
        echo "$result"
        return 0
    else
        [[ "$TORRENT_DEBUG" == "true" ]] && echo "DEBUG [launch_splash_screen]: FAILED! Cleaning up..." >&2
        [[ -S "$ipc_socket" ]] && rm -f "$ipc_socket"
        return 1
    fi
}

# Launch player with video source and optional subtitle
launch_player() {
    local source="$1"
    local subtitle="$2"
    local title="${3:-Termflix Stream}"
    
    local player=$(get_active_player)
    local player_pid=""
    
    log_info "Launching player: $player for $source"
    
    case "$player" in
        "mpv")
            local window_title="TermFlix™"
            if [ -n "$title" ]; then
                window_title="TermFlix™ - $title"
            fi
            local args=("--force-window=immediate" "--title=$window_title")
            if [ -n "$subtitle" ]; then
                args+=("--sub-file=$subtitle" "--sub-visibility=yes")
            fi
            
            # If source is a URL (streaming), increase cache
            if [[ "$source" =~ ^http ]]; then
                args+=("--cache=yes" "--demuxer-max-bytes=150M")
            fi
            
            mpv "${args[@]}" "$source" >/dev/null 2>&1 &
            player_pid=$!
            ;;
            
        "iina")
            # IINA usually requires `iina-cli` or `open -a IINA`
            if command -v iina &> /dev/null; then
                local args=()
                if [ -n "$subtitle" ]; then
                     args+=("--mpv-sub-file=$subtitle")
                fi
                iina "${args[@]}" "$source" >/dev/null 2>&1 &
                player_pid=$!
            else
                # Fallback to opening app directly on macOS
                open -a IINA "$source"
                sleep 2
                player_pid=$(pgrep -x IINA | head -1)
            fi
            ;;
            
        "vlc")
            local args=()
            if [ -n "$subtitle" ]; then
                args+=("--sub-file=$subtitle")
            fi
            
            if [[ "$OSTYPE" == "darwin"* ]] && [ -d "/Applications/VLC.app" ] && ! command -v vlc &> /dev/null; then
                # macOS direct app launch
                /Applications/VLC.app/Contents/MacOS/VLC "${args[@]}" "$source" >/dev/null 2>&1 &
                player_pid=$!
            else
                vlc "${args[@]}" "$source" >/dev/null 2>&1 &
                player_pid=$!
            fi
            ;;
            
        "mplayer")
            local window_title="TermFlix™"
            if [ -n "$title" ]; then
                window_title="TermFlix™ - $title"
            fi
            local args=("-title" "$window_title")
            if [ -n "$subtitle" ]; then
                args+=("-sub" "$subtitle")
            fi
            mplayer "${args[@]}" "$source" >/dev/null 2>&1 &
            player_pid=$!
            ;;
            
        *)
            log_error "Unknown player: $player"
            return 1
            ;;
    esac
    
    if [ -n "$player_pid" ]; then
        echo "$player_pid"
        return 0
    else
        return 1
    fi
}

# Check if player process is running
is_player_running() {
    local pid="$1"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# PLAYER MONITORING (Extracted from torrent.sh Dec 2025)
# ═══════════════════════════════════════════════════════════════

# Monitor player process with fork detection and cleanup
# Handles VLC/mpv forking behavior and provides graceful shutdown
# 
# Args:
#   $1 = player name ("vlc", "mpv", etc.)
#   $2 = player PID (may not be actual running PID if forked)
#   $3 = video file path (for lsof checking)
#   $4 = peerflix/torrent PID to cleanup on exit
#   $5 = temp output file to cleanup
#
# Returns:
#   0 = Normal completion
#   2 = Player closed (special exit code for catalog return)
monitor_player_process() {
    local player="$1"
    local player_pid="$2"
    local video_path="$3"
    local torrent_pid="$4"
    local temp_output="$5"
    
    # Trap handler for graceful interruption
    cleanup_and_exit() {
        echo -e "\n${YELLOW}Interrupted. Stopping torrent client...${RESET}"
        [ -n "$torrent_pid" ] && kill "$torrent_pid" 2>/dev/null || true
        sleep 1
        [ -n "$torrent_pid" ] && kill -9 "$torrent_pid" 2>/dev/null || true
        [ -n "$torrent_pid" ] && wait "$torrent_pid" 2>/dev/null &>/dev/null || true
        [ -n "$temp_output" ] && rm -f "$temp_output" 2>/dev/null
        exit 0
    }
    trap cleanup_and_exit INT TERM
    
    # Wait for potential fork (VLC/IINA often fork)
    sleep 2
    
    # Monitor player by process name (handles forks)
    local player_running=true
    local check_count=0
    
    while [ "$player_running" = true ]; do
        local player_processes=""
        
        # Check for player processes based on player type
        if [ "$player" = "vlc" ]; then
            # VLC can be "VLC", "vlc", or in app bundle
            player_processes=$(pgrep -i "vlc" 2>/dev/null | head -1 || echo "")
            if [ -z "$player_processes" ]; then
                # Try ps grep
                player_processes=$(ps aux | grep -i "[V]LC" | grep -v grep | awk '{print $2}' | head -1 || echo "")
            fi
            # Check if video file is open (lsof)
            if [ -z "$player_processes" ] && command -v lsof &>/dev/null && [ -n "$video_path" ]; then
                local open_by=$(lsof "$video_path" 2>/dev/null | grep -i vlc | head -1 || echo "")
                [ -n "$open_by" ] && player_processes="open"
            fi
        else
            # Check for mpv/iina/other players
            player_processes=$(pgrep "$player" 2>/dev/null | head -1 || echo "")
            # Fallback to lsof check
            if [ -z "$player_processes" ] && command -v lsof &>/dev/null && [ -n "$video_path" ]; then
                local open_by=$(lsof "$video_path" 2>/dev/null | grep -i "$player" | head -1 || echo "")
                [ -n "$open_by" ] && player_processes="open"
            fi
        fi
        
        # If no player found, double-check after brief delay
        if [ -z "$player_processes" ]; then
            sleep 1
            if [ "$player" = "vlc" ]; then
                player_processes=$(pgrep -i "vlc" 2>/dev/null | head -1 || echo "")
                if [ -z "$player_processes" ]; then
                    player_processes=$(ps aux | grep -i "[V]LC" | grep -v grep | awk '{print $2}' | head -1 || echo "")
                fi
            else
                player_processes=$(pgrep "$player" 2>/dev/null | head -1 || echo "")
            fi
            
            # Player truly exited
            if [ -z "$player_processes" ]; then
                player_running=false
                break
            fi
        fi
        
        # Player still running, continue monitoring
        sleep 1
        check_count=$((check_count + 1))
        
        # Safety timeout (10 minutes)
        if [ $check_count -gt 600 ]; then
            echo -e "${YELLOW}Warning:${RESET} Monitoring timeout, stopping torrent anyway"
            player_running=false
            break
        fi
    done
    
    # Clear trap
    trap - INT TERM
    
    # Player exited, cleanup torrent client
    echo -e "${CYAN}Player closed. Stopping torrent client...${RESET}"
    [ -n "$torrent_pid" ] && kill "$torrent_pid" 2>/dev/null || true
    sleep 1
    [ -n "$torrent_pid" ] && kill -9 "$torrent_pid" 2>/dev/null || true
    [ -n "$torrent_pid" ] && wait "$torrent_pid" 2>/dev/null &>/dev/null || true
    
    [ -n "$temp_output" ] && rm -f "$temp_output" 2>/dev/null
    
    # Return special exit code for catalog return
    return 2
}

# Export functions
export -f detect_players get_active_player launch_player launch_splash_screen is_player_running
export -f monitor_player_process
