#!/usr/bin/env bash
#
# Termflix Player Module
# Handles video player detection and launching
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
            local args=("--force-window=immediate" "--title=$title")
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
            # Using `iina` command if available (installed via brew cask)
            if command -v iina &> /dev/null; then
                local args=()
                if [ -n "$subtitle" ]; then
                    # IINA might handle loading adjacent subs auto, but valid flag is needed
                    # iina-cli documentation is needed, falling back to basic open for now if CLI specific flags assume mpv-like behavior
                     args+=("--mpv-sub-file=$subtitle")
                fi
                iina "${args[@]}" "$source" >/dev/null 2>&1 &
                player_pid=$!
            else
                # Fallback to opening app directly on macOS
                open -a IINA "$source"
                # Getting PID of opened app is tricky, simplified assumption
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
            local args=("-title" "$title")
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
