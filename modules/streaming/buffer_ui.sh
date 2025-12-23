#!/usr/bin/env bash
#
# Termflix Buffering UI Module
# Updates Stage 2 preview window with buffering status
#

show_inline_buffer_ui() {
    local title="$1"
    local poster="$2"
    local plot="$3"
    local magnet="$4"
    local source="$5"
    local quality="$6"
    local selected_idx="${7:-0}"
    local imdb_id="${8:-}"
    
    # Normalize TMPDIR (macOS adds trailing slash)
    local tmpdir="${TMPDIR:-/tmp}"
    tmpdir="${tmpdir%/}"  # Remove trailing slash
    
    # Setup file paths
    local status_file="$tmpdir/termflix_buffer_status.txt"
    local stream_log="$tmpdir/termflix_stream_debug.log"
    echo "0|0|0|0|0|STARTING" > "$status_file"
    
    # Source modules for backdrop and splash screen
    local BACKDROP_MODULE="${BASH_SOURCE%/*}/../api/tmdb_backdrops.sh"
    local PLAYER_MODULE="${BASH_SOURCE%/*}/player.sh"
    local PROGRESS_MODULE="${BASH_SOURCE%/*}/splash_progress.sh"
    [[ -f "$BACKDROP_MODULE" ]] && source "$BACKDROP_MODULE"
    [[ -f "$PLAYER_MODULE" ]] && source "$PLAYER_MODULE"
    [[ -f "$PROGRESS_MODULE" ]] && source "$PROGRESS_MODULE"
    
    # Launch MPV splash screen with backdrop (parallel to FZF buffering)
    local splash_pid=""
    local splash_socket=""
    
    # Debug helper (defined early so it can be used below)
    debug_log() {
        if [[ "${TERMFLIX_DEBUG:-false}" == "true" ]]; then
            echo "DEBUG: $1" >&2
        fi
    }
    
    # Fetch backdrop from Google Images (non-blocking with timeout)
    # Falls back to poster if no wide backdrop found
    local backdrop_image=""
    local stream_dir
    stream_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local root_dir
    root_dir="$(cd "${stream_dir}/../.." && pwd)"
    local helper_dir="${TERMFLIX_HELPER_SCRIPTS_DIR:-${root_dir}/scripts/python}"
    local BACKDROP_SCRIPT="${helper_dir}/fetch_backdrop.py"
    
    # Detect content type (show vs movie) based on environment
    local content_type="movie"
    if [[ -n "$TMDB_SERIES_ID" || -n "$SERIES_METADATA" || "$TERMFLIX_CONTENT_TYPE" == "show" ]]; then
        content_type="show"
    fi
    
    # Fetch with 3-second timeout, retry up to 3 times
    if [[ -f "$BACKDROP_SCRIPT" ]] && command -v python3 &>/dev/null; then
        # Show actual search query format
        local search_term="${title} ${content_type} backdrop"
        echo -e "🔍 Searching: ${search_term}"
        debug_log "Fetching backdrop via Google Images for: $title (type: $content_type)"
        local fetched_backdrop=""
        local retry=0
        while [[ -z "$fetched_backdrop" || ! -f "$fetched_backdrop" ]] && [[ $retry -lt 3 ]]; do
            fetched_backdrop=$(timeout 3 python3 "$BACKDROP_SCRIPT" "$title" --type "$content_type" 2>/dev/null)
            ((retry++))
        done
        if [[ -n "$fetched_backdrop" ]] && [[ -f "$fetched_backdrop" ]]; then
            backdrop_image="$fetched_backdrop"
            debug_log "Using Google Images backdrop: $fetched_backdrop"
        else
            debug_log "No wide backdrop found, using poster as fallback"
            backdrop_image="$poster"
        fi
    else
        # Script not available, use poster
        backdrop_image="$poster"
    fi
    
    debug_log "Checking splash screen preconditions..."
    debug_log "backdrop_image=$backdrop_image"
    
    # Check if backdrop is a URL and download it if needed
    if [[ "$backdrop_image" =~ ^https?:// ]]; then
        debug_log "Backdrop is a URL, downloading..."
        local temp_bg="${tmpdir}/termflix_backdrop_$$.jpg"
        if curl -sL "$backdrop_image" -o "$temp_bg" --max-time 5; then
            debug_log "Downloaded to $temp_bg"
            backdrop_image="$temp_bg"
            # Update poster variable too so the preview script (which checks -f) works
            poster="$temp_bg"
            # Cleanup temp background on exit
            trap 'rm -f "$temp_bg" 2>/dev/null; cleanup_stream' EXIT INT TERM
        else
            debug_log "Failed to download backdrop URL"
        fi
    fi
    
    debug_log "launch_splash_screen available: $(command -v launch_splash_screen || echo 'NOT FOUND')"
    
    if command -v launch_splash_screen &>/dev/null && [[ -f "$backdrop_image" ]]; then
        debug_log "Launching splash screen..."
        local splash_result=$(launch_splash_screen "$backdrop_image" "$title" 2>&2)
        debug_log "splash_result=$splash_result"
        if [[ -n "$splash_result" ]] && [[ "$splash_result" =~ \|  ]]; then
            splash_pid="${splash_result%|*}"
            splash_socket="${splash_result#*|}"
            debug_log "Extracted PID=$splash_pid,Socket=$splash_socket"
            if ! kill -0 "$splash_pid" 2>/dev/null || [[ ! -S "$splash_socket" ]]; then
                debug_log "Splash screen failed validation"
                splash_pid=""
                splash_socket=""
            else
                debug_log "Splash screen launched successfully!"
            fi
        else
            debug_log "splash_result doesn't match expected format"
        fi
    else
        debug_log "Splash screen preconditions not met"
    fi
    
    # Launch progress monitor if splash launched successfully
    if [[ -n "$splash_socket" ]] && [[ -S "$splash_socket" ]]; then
        monitor_splash_progress "$splash_socket" "$status_file" "$title" &>/dev/null &
        debug_log "Progress monitor started"
    fi
    
    echo "=== Buffer UI Started ===" > "$stream_log"
    echo "Time: $(date)" >> "$stream_log"
    echo "Backdrop: $backdrop_image" >> "$stream_log"
    echo "Splash PID: ${splash_pid:-none}" >> "$stream_log"
    echo "Splash Socket: ${splash_socket:-none}" >> "$stream_log"
    echo "Magnet: ${magnet:0:60}..." >> "$stream_log"
    echo "Status file: $status_file" >> "$stream_log"
    echo "Starting stream_torrent in background..." >> "$stream_log"
    
    {
        export TERMFLIX_BUFFER_STATUS="$status_file"
        export TERMFLIX_SPLASH_SOCKET="$splash_socket"  # Pass socket to stream_torrent
        echo "Calling stream_torrent..." >> "$stream_log" 2>&1
        stream_torrent "$magnet" "" false false "$title" >> "$stream_log" 2>&1
        echo "stream_torrent exited with code: $?" >> "$stream_log" 2>&1
    } &
    local stream_pid=$!
    
    # Setup cleanup
    local preview_script="$tmpdir/termflix_buffer_preview.sh"
    
    # Cleanup function
    cleanup_stream() {
        tput cnorm
        # Kill splash screen if still running
        if [[ -n "$splash_pid" ]] && kill -0 "$splash_pid" 2>/dev/null; then
            kill "$splash_pid" 2>/dev/null
        fi
        if kill -0 "$stream_pid" 2>/dev/null; then
            kill -9 "$stream_pid" 2>/dev/null
            wait "$stream_pid" 2>/dev/null
        fi
        rm -f "$status_file" "$preview_script" 2>/dev/null
        
        # Clean torrent cache (like termflix --remove)
        # Verify this logic matches user request to clear /tmp/torrent-stream
        local torrent_dir="/tmp/torrent-stream"
        if [ -d "$torrent_dir" ]; then
             rm -rf "$torrent_dir"/* 2>/dev/null
        fi
    }
    
    trap cleanup_stream EXIT INT TERM
    
    # Export environment for preview script
    export TERMFLIX_BUFFER_STATUS="$status_file"
    export TERMFLIX_STREAM_LOG="$stream_log"
    export TERMFLIX_MAGNET="$magnet"
    
    # Generate random port for FZF API (between 10000 and 20000)
    local fzf_port=$((10000 + RANDOM % 10000))
    export FZF_API_PORT="$fzf_port"
    cat > "$preview_script" << 'PREVIEW_EOF'
#!/usr/bin/env bash
# Buffering preview - updates continuously

# Movie metadata from environment
status_file="$TERMFLIX_BUFFER_STATUS"
stream_log="$TERMFLIX_STREAM_LOG"
poster="$STAGE2_POSTER"
title="$STAGE2_TITLE"
plot="$STAGE2_PLOT"
sources="$STAGE2_SOURCES"

# Read status file
state="STARTING"
progress=0
speed_bytes=0
connected_peers=0
total_peers=0
buffered_mb=0

# Spinner frames
spinner_frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
frame_idx=$((EPOCHSECONDS % 10))
spinner="${spinner_frames[$frame_idx]}"

if [[ -f "$TERMFLIX_BUFFER_STATUS" ]]; then
    IFS='|' read -r progress speed_bytes connected_peers total_peers buffered_mb state stream_url peerflix_pid < "$TERMFLIX_BUFFER_STATUS"
fi

# Activity indicator in top-right (like Stage 1)
activity=""
if [[ "$state" == "STARTING" ]]; then
    activity="${spinner} Connecting to peers..."
elif [[ "$state" == "ANALYZING" ]]; then
    activity="${spinner} Analyzing video (${buffered_mb} MB)..."
elif [[ "$state" == "BUFFERING" ]]; then
    activity="${spinner} Downloading"
elif [[ "$state" == "READY" ]]; then
    activity="✓ Ready"
fi

# Get latest activity from stream log (last 3 lines, filtered)
recent_activity=""
if [[ -f "$TERMFLIX_STREAM_LOG" ]]; then
    recent_activity=$(tail -10 "$TERMFLIX_STREAM_LOG" 2>/dev/null | \
        grep -i "peer\|connect\|download\|path\|buffer" | \
        tail -3 | \
        sed 's/^.*: //' | \
        cut -c1-50)
fi

# Colors
PINK="\033[38;5;212m"
GREEN="\033[38;5;46m"
YELLOW="\033[38;5;226m"
GRAY="\033[38;5;240m"
CYAN="\033[38;5;51m"
BRIGHT_CYAN="\033[38;2;94;234;212m"  # Charm Bracelet cyan #5EEAD4
RESET="\033[0m"

# Activity indicator at top-right (colored bright cyan)
# Calculate position for right-alignment (assume 80 char width)
activity_len=${#activity}
padding=$((80 - activity_len))
printf "%${padding}s" ""  # Right padding
echo -e "${BRIGHT_CYAN}${activity}${RESET}"
echo ""

# Movie info header
echo -e "${PINK}${title}${RESET}"
echo ""
echo "Sources: ${sources}"
echo ""

# Show plot/description instead of magnet link
if [[ -n "$plot" && "$plot" != "null" ]]; then
    echo -e "${GRAY}SYNOPSIS${RESET}"
    echo "$plot" | fmt -w 50
    echo ""
else
    # Fallback streaming tips
    echo -e "${CYAN}🎬 Streaming Tips${RESET}"
    echo "  • Buffering takes 30-60 seconds"
    echo "  • Better seeds = faster stream"
    echo "  • 1080p requires ~5MB/s connection"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""


# Poster display (fixed aspect ratio) - AFTER text to prevent overlay
if [[ -f "$poster" ]]; then
    # Direct image display (can't source modules from /tmp preview script)
    if [[ "$TERM" == "xterm-kitty" ]] && command -v kitten &> /dev/null; then
        # Kitty terminal - use kitten icat
        command -v chafa &> /dev/null && TERM=xterm-256color chafa --symbols=block --size="40x30" "$poster" 2>/dev/null || echo "[POSTER]"
        # Add spacing after image
        for i in {1..31}; do echo ""; done
    elif command -v viu &> /dev/null; then
        # VIU - Unicode-based image viewer
        viu -w 40 "$poster" 2>/dev/null
    elif command -v chafa &> /dev/null; then
        # Chafa - Block graphics fallback
        TERM=xterm-256color chafa --symbols=block --size="40x30" "$poster" 2>/dev/null
    else
        echo "[POSTER]"
    fi
else
    echo "[POSTER]"
    echo ""
fi

# Debug info
if [[ -f "$stream_log" ]]; then
    # Filter out error messages and verification loops
    last_log=$(tail -5 "$stream_log" 2>/dev/null | grep -v "transmission\|error\|Error\|Verifying" | head -1)
    if [[ -n "$last_log" ]]; then
        echo -e "${GRAY}Debug: ${last_log:0:50}...${RESET}"
        echo ""
    fi
fi

# Buffering status (live)
if [[ -f "$status_file" ]]; then
    status_line=$(cat "$status_file")
    IFS='|' read -r progress speed_bytes peers total_peers size state stream_url peerflix_pid <<< "$status_line"
    
    # Provide defaults
    progress="${progress:-0}"
    speed_bytes="${speed_bytes:-0}"
    peers="${peers:-0}"
    total_peers="${total_peers:-0}"
    size="${size:-0}"
    state="${state:-BUFFERING}"
    
    # Format speed from bytes/sec to human readable
    speed="0"
    if [[ $speed_bytes -gt 1048576 ]]; then
        # MB/s
        speed=$(awk "BEGIN {printf \"%.2f MB/s\", $speed_bytes / 1048576}")
    elif [[ $speed_bytes -gt 1024 ]]; then
        # KB/s
        speed=$(awk "BEGIN {printf \"%.2f KB/s\", $speed_bytes / 1024}")
    elif [[ $speed_bytes -gt 0 ]]; then
        speed="${speed_bytes} B/s"
    fi
    
    echo -e "${YELLOW}Status: ${state}${RESET}"
    echo ""
    
    if [[ "$state" == "READY" ]]; then
        echo -e "${GREEN}✓ Buffer complete! Auto-playing...${RESET}"
        echo ""
        # Trigger FZF accept via API
        if [[ -n "$FZF_API_PORT" ]]; then
            curl -s -X POST -d 'accept' "http://localhost:${FZF_API_PORT}" >/dev/null 2>&1
        fi
    else
        # Progress bar
        bar_len=30
        filled=$((progress * bar_len / 100))
        
        bar="${PINK}"
        for ((i=0; i<filled; i++)); do bar+="━"; done
        bar+="${GRAY}"
        for ((i=filled; i<bar_len; i++)); do bar+="━"; done
        bar+="${RESET}"
        
        echo -e "⬇  ${YELLOW}Downloading & Buffering${RESET}"
        echo ""
        echo -e "${bar} ${progress}%"
        echo ""
        # Status indicators using colored dots (like Stage 1 header)
        # 🟢 = Running, 🔴 = Stopped/Died
        
        # Peerflix Status
        peerflix_dot="${RED}●${RESET}"
        if [[ -n "$peerflix_pid" ]] && kill -0 "$peerflix_pid" 2>/dev/null; then
             peerflix_dot="${GREEN}●${RESET}"
        fi
        
        # MPV Status (check if mpv process exists)
        mpv_dot="${RED}●${RESET}"
        # We need to find MPV pid. Attempt to read from status file if available or check standard pid
        # Since we don't have MPV PID in status file yet, we'll check broadly or just rely on stream URL reachability?
        # Better: Update torrent.sh to write MPV pid to status file too. 
        # For now, let's assume if stream URL is up and we assume MPV is launched...
        # Actually, user asked to "produce its status aswell".
        # Let's check for any mpv process playing this file? Or better, check if the transition happened.
        # If state is PLAYING, MPV should be running.
        if [[ "$state" == "PLAYING" ]] || [[ "$state" == "READY" ]]; then
             # Simple check: is there an MPV process running?
             if pgrep -x "mpv" >/dev/null; then
                 mpv_dot="${GREEN}●${RESET}"
             fi
        fi

        printf "%-15s %b Peerflix\n" "Source:" "$peerflix_dot"
        printf "%-15s %b MPV Player\n" "Player:" "$mpv_dot"
        
        if [[ -n "$stream_url" ]]; then
             # Clean URL for display (remove http://localhost:)
             display_url="${stream_url#http://localhost:}"
             display_url="${display_url%/}"
             printf "%-15s Port: %s\n" "Stream:" "$display_url"
        fi
        
        printf "%-15s %s\n" "Speed:" "$speed"
        printf "%-15s %d MB\n" "Buffered:" "${buffered_mb:-0}"
        
        echo ""
        echo -e "${GRAY}Press ESC to cancel${RESET}"
    fi
else
    echo -e "${YELLOW}Initializing stream...${RESET}"
    echo ""
    echo "Status file: $status_file"
    if [[ -f "$stream_log" ]]; then
        echo ""
        echo "Recent log:"
        tail -5 "$stream_log" 2>/dev/null | sed 's/^/  /'
    fi
fi
PREVIEW_EOF
    
    # Make preview script executable and verify
    if [[ ! -f "$preview_script" ]]; then
        echo "ERROR: Failed to create preview script: $preview_script" >> "$stream_log"
        echo "ERROR: Failed to create preview script at $preview_script"
        return 1
    fi
    
    chmod +x "$preview_script"
    echo "✓ Preview script created: $preview_script" >> "$stream_log"
    
    # Export env vars for preview
    export STAGE2_POSTER="$poster"
    export STAGE2_TITLE="$title"
    export STAGE2_PLOT="$plot"
    export STAGE2_SOURCES="[$source]"
    
    # Read versions list
    local options_file="$tmpdir/termflix_stage2_options.txt"
    local options=""
    if [[ -f "$options_file" ]]; then
        options=$(cat "$options_file")
    else
        options="0|${quality} - ${source}|$title"
    fi
    
    # Generate random port for FZF API (between 10000 and 20000)
    local fzf_port=$((10000 + RANDOM % 10000))
    
    # Start background refresh loop (Sidecar) - refresh every 0.3s for smooth updates
    {
        while kill -0 "$stream_pid" 2>/dev/null; do
            sleep 0.3
            curl -s -X POST -d 'refresh-preview' "http://localhost:${fzf_port}" >/dev/null 2>&1
        done
    } &
    local refresh_pid=$!
    
    # Update cleanup to kill refresh loop
    cleanup_stream() {
        if kill -0 "$refresh_pid" 2>/dev/null; then kill "$refresh_pid" 2>/dev/null; fi
        tput cnorm
        if kill -0 "$stream_pid" 2>/dev/null; then
            kill -9 "$stream_pid" 2>/dev/null
            wait "$stream_pid" 2>/dev/null
        fi
        rm -f "$status_file" "$preview_script" 2>/dev/null
    }
    
    # Launch Stage 2 FZF with listen port for API updates
    printf "%s" "$options" | fzf \
        --ansi \
        --delimiter='|' \
        --with-nth=2 \
        --height=100% \
        --layout=reverse \
        --border=rounded \
        --margin=1 \
        --padding=1 \
        --border-label=" Esc:Back " \
        --border-label-pos=bottom \
        --prompt='⬇ Buffering ' \
        --pointer='➤' \
        --header="Streaming: ${title}" \
        --header-first \
        --color=fg:#f8f8f2,bg:-1,hl:#ff79c6 \
        --color=fg+:#ffffff,bg+:#44475a,hl+:#ff79c6 \
        --color=info:#bd93f9,prompt:#50fa7b,pointer:#ff79c6 \
        --listen "$fzf_port" \
        --preview "$preview_script" \
        --preview-window=left:55%:wrap:border-right \
        --bind='enter:accept' \
        --bind='esc:abort' \
        --bind='ctrl-c:abort' \
        >/dev/null 2>&1
    
    local fzf_exit=$?
    
    # Cleanup exports
    unset STAGE2_POSTER STAGE2_TITLE STAGE2_PLOT STAGE2_SOURCES
    
    # If user cancelled, cleanup and return
    if [[ $fzf_exit -ne 0 ]]; then
        cleanup_stream
        return 1
    fi
    
    # Stream is ready, bring player to foreground
    if kill -0 "$stream_pid" 2>/dev/null; then
        tput cnorm
        fg %1 2>/dev/null || wait "$stream_pid"
    fi
    
    # Cleanup after stream finishes
    cleanup_stream
}
