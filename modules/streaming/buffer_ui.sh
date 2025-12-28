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
        while [[ -z "$fetched_backdrop" || ! -f "$fetched_backdrop" ]] && [[ $retry -lt 2 ]]; do
            fetched_backdrop=$(timeout 10 python3 "$BACKDROP_SCRIPT" "$title" --type "$content_type" 2>/dev/null)
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

    # Fallback chain: if backdrop_image is still invalid (N/A, empty, not a file)
    # try to use a bundled default image
    if [[ -z "$backdrop_image" || "$backdrop_image" == "N/A" || ( ! -f "$backdrop_image" && ! "$backdrop_image" =~ ^https?:// ) ]]; then
        # Check if poster itself is a URL we can download
        if [[ "$poster" =~ ^https?:// ]]; then
            debug_log "Poster is a URL, will download later"
            backdrop_image="$poster"
        else
            # Try bundled default image
            local default_img="${root_dir}/lib/torrent/img/movie_night.jpg"
            if [[ -f "$default_img" ]]; then
                debug_log "Using bundled default image: $default_img"
                backdrop_image="$default_img"
            else
                debug_log "No valid backdrop or fallback image available"
                backdrop_image=""
            fi
        fi
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
        disown 2>/dev/null || true  # Fully detach progress monitor
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
    disown 2>/dev/null || true  # Fully detach stream process
    
    # Setup cleanup
    local buffer_preview_script="$tmpdir/termflix_buffer_preview.sh"
    
    # Cleanup function
    cleanup_stream() {
        tput cnorm
        
        # Kill sidecar refresh loop
        if [[ -n "${refresh_pid:-}" ]] && kill -0 "$refresh_pid" 2>/dev/null; then
             kill "$refresh_pid" 2>/dev/null
        fi

        # Kill splash screen if still running
        if [[ -n "$splash_pid" ]] && kill -0 "$splash_pid" 2>/dev/null; then
            kill "$splash_pid" 2>/dev/null
        fi
        
        # Kill stream process
        if [[ -n "$stream_pid" ]] && kill -0 "$stream_pid" 2>/dev/null; then
            kill -9 "$stream_pid" 2>/dev/null
            wait "$stream_pid" 2>/dev/null
        fi
        rm -f "$status_file" "$buffer_preview_script" 2>/dev/null
        
        # Clean torrent cache (like termflix --remove)
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
    
    # Export trailer script path and cache dir for preview
    export TERMFLIX_TRAILER_SCRIPT="${helper_dir}/fetch_trailers.py"
    export TERMFLIX_POSTER_CACHE="${HOME}/.cache/termflix/posters"
    
    cat > "$buffer_preview_script" << 'PREVIEW_EOF'
#!/usr/bin/env bash
# Buffering preview - updates continuously

# DEBUG: Log status file path and content
echo "$(date +%H:%M:%S): Preview running, status_file=$TERMFLIX_BUFFER_STATUS" >> /tmp/termflix_preview_debug.log
if [[ -f "$TERMFLIX_BUFFER_STATUS" ]]; then
    echo "$(date +%H:%M:%S): Status: $(cat "$TERMFLIX_BUFFER_STATUS")" >> /tmp/termflix_preview_debug.log
else
    echo "$(date +%H:%M:%S): Status file NOT FOUND" >> /tmp/termflix_preview_debug.log
fi

# Movie metadata from environment
status_file="$TERMFLIX_BUFFER_STATUS"
stream_log="$TERMFLIX_STREAM_LOG"
poster="$STAGE2_POSTER"
title="$STAGE2_TITLE"
plot="$STAGE2_PLOT"
sources="$STAGE2_SOURCES"
trailer_script="$TERMFLIX_TRAILER_SCRIPT"
poster_cache="$TERMFLIX_POSTER_CACHE"

# Download poster if it's a URL
if [[ "$poster" =~ ^https?:// ]]; then
    mkdir -p "$poster_cache"
    poster_hash=$(echo -n "$poster" | md5 2>/dev/null || echo -n "$poster" | md5sum | cut -d' ' -f1)
    local_poster="${poster_cache}/${poster_hash}.jpg"
    if [[ ! -f "$local_poster" ]]; then
        curl -sL "$poster" -o "$local_poster" --max-time 5 2>/dev/null
    fi
    [[ -f "$local_poster" ]] && poster="$local_poster"
fi

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
RED="\033[38;5;196m"
BRIGHT_CYAN="\033[38;2;94;234;212m"
RESET="\033[0m"

# ═══════════════════════════════════════════════════════════════════
# SECTION 1: TITLE + LIVE PROGRESS (MOST IMPORTANT - ALWAYS VISIBLE)
# ═══════════════════════════════════════════════════════════════════

echo -e "${PINK}${title}${RESET}"
echo "Sources: ${sources}"
echo ""

# Live buffering progress (THE MAIN PURPOSE OF THIS UI)
if [[ -f "$status_file" ]]; then
    status_line=$(cat "$status_file")
    IFS='|' read -r progress speed_bytes peers total_peers size state stream_url peerflix_pid <<< "$status_line"
    
    progress="${progress:-0}"
    speed_bytes="${speed_bytes:-0}"
    state="${state:-STARTING}"
    
    # Format speed
    speed="0"
    if [[ $speed_bytes -gt 1048576 ]]; then
        speed=$(awk "BEGIN {printf \"%.1f MB/s\", $speed_bytes / 1048576}")
    elif [[ $speed_bytes -gt 1024 ]]; then
        speed=$(awk "BEGIN {printf \"%.0f KB/s\", $speed_bytes / 1024}")
    fi
    
    # Progress bar (compact)
    bar_len=25
    filled=$((progress * bar_len / 100))
    bar="${PINK}"
    for ((i=0; i<filled; i++)); do bar+="━"; done
    bar+="${GRAY}"
    for ((i=filled; i<bar_len; i++)); do bar+="━"; done
    bar+="${RESET}"
    
    if [[ "$state" == "PLAYING" ]]; then
        echo -e "${GREEN}▶ PLAYING${RESET}  ${bar} ${progress}%"
    elif [[ "$state" == "READY" ]]; then
        echo -e "${GREEN}✓ READY${RESET}    ${bar} ${progress}%"
        # Auto-accept
        [[ -n "$FZF_API_PORT" ]] && curl -s -X POST -d 'accept' "http://localhost:${FZF_API_PORT}" >/dev/null 2>&1
    elif [[ "$state" == "BUFFERING" ]]; then
        echo -e "${YELLOW}⬇ BUFFERING${RESET} ${bar} ${progress}%"
    else
        echo -e "${CYAN}⏳ ${state}${RESET}"
    fi
    
    # Compact stats line
    echo -e "${GRAY}Speed: ${speed} | Buffered: ${size:-0} MB${RESET}"
else
    echo -e "${CYAN}⏳ Initializing stream...${RESET}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION 2: SYNOPSIS (if available, truncated)
# ═══════════════════════════════════════════════════════════════════

if [[ -n "$plot" && "$plot" != "null" ]]; then
    # Truncate synopsis to 3 lines max
    echo -e "${GRAY}SYNOPSIS${RESET}"
    echo "$plot" | fmt -w 45 | head -3
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════
# SECTION 3: PROCESS STATUS (compact)
# ═══════════════════════════════════════════════════════════════════

if [[ -f "$status_file" ]]; then
    # Peerflix status
    peerflix_dot="${RED}●${RESET}"
    if [[ -n "$peerflix_pid" ]] && kill -0 "$peerflix_pid" 2>/dev/null; then
        peerflix_dot="${GREEN}●${RESET}"
    fi
    
    # MPV status
    mpv_dot="${RED}●${RESET}"
    if pgrep -x "mpv" >/dev/null 2>&1; then
        mpv_dot="${GREEN}●${RESET}"
    fi
    
    echo -e "Peerflix: ${peerflix_dot}  MPV: ${mpv_dot}"
    [[ -n "$stream_url" ]] && echo -e "${GRAY}Stream: ${stream_url}${RESET}"
fi

echo ""
echo -e "${GRAY}Press ESC to cancel${RESET}"
PREVIEW_EOF
    
    # Make preview script executable and verify
    if [[ ! -f "$buffer_preview_script" ]]; then
        echo "ERROR: Failed to create preview script: $buffer_preview_script" >> "$stream_log"
        echo "ERROR: Failed to create preview script at $buffer_preview_script"
        return 1
    fi
    
    chmod +x "$buffer_preview_script"
    echo "✓ Preview script created: $buffer_preview_script" >> "$stream_log"
    
    # Export env vars for preview
    # Use existing STAGE2_POSTER from Stage 2 if available and valid
    if [[ -n "${STAGE2_POSTER:-}" && -f "${STAGE2_POSTER}" ]]; then
        : # Keep existing value
    else
        export STAGE2_POSTER="$poster"
    fi
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
    local refresh_pid=""
    {
        echo "$(date): Sidecar starting, FZF port=$fzf_port, stream_pid=$stream_pid" >> /tmp/termflix_sidecar.log
        local refresh_count=0
        while kill -0 "$stream_pid" 2>/dev/null; do
            sleep 0.3
            # FZF listen API: just send the action name
            local curl_result=$(curl -s -X POST "http://localhost:${fzf_port}" -d 'refresh-preview' 2>&1)
            ((refresh_count++))
            if [[ $((refresh_count % 10)) -eq 0 ]]; then
                echo "$(date): Sidecar refresh #$refresh_count, curl result: $curl_result" >> /tmp/termflix_sidecar.log
            fi
        done
        echo "$(date): Sidecar exiting, stream_pid no longer running" >> /tmp/termflix_sidecar.log
        # Stream finished (MPV closed) - auto-close FZF buffer UI
        sleep 0.5  # Brief delay for cleanup
        curl -s -X POST "http://localhost:${fzf_port}" -d 'abort' 2>/dev/null || true
        echo "$(date): Sent abort to FZF to auto-close buffer UI" >> /tmp/termflix_sidecar.log
    } &
    refresh_pid=$!
    disown 2>/dev/null || true  # Fully detach sidecar from job control
    
    # Update cleanup to kill refresh loop
    # Cleanup logic is handled by the main cleanup_stream function defined earlier
    
    # ════════════════════════════════════════════════════════════════
    # FZF Buffer UI (Stage 3) with listen port for API-driven refresh
    # ════════════════════════════════════════════════════════════════
    # NOTE: TML parser escapes header content to avoid eval issues in tml_run_fzf.
    local ui_dir="${root_dir}/modules/ui"
    export title
    export preview_script="$buffer_preview_script"
    source "${ui_dir}/tml/parser/tml_parser.sh"
    tml_parse "${ui_dir}/layouts/buffer-ui.xml"
    printf "%s" "$options" | FZF_DEFAULT_OPTS="" ESCDELAY=1000 tml_run_fzf \
        --ansi \
        --no-mouse \
        --listen "$fzf_port" \
        --color "fg:#f8f8f2,bg:-1,hl:#ff79c6,fg+:#ffffff,bg+:#44475a,hl+:#ff79c6,info:#bd93f9,prompt:#50fa7b,pointer:#ff79c6" \
        >/dev/null 2>&1
    
    # ════════════════════════════════════════════════════════════════
    # OLD HARDCODED FZF CONFIG (commented for reference)
    # ════════════════════════════════════════════════════════════════
    # printf "%s" "$options" | fzf \
    #     --ansi \
    #     --delimiter='|' \
    #     --with-nth=2 \
    #     --height=100% \
    #     --layout=reverse \
    #     --border=rounded \
    #     --margin=1 \
    #     --padding=1 \
    #     --border-label=" Esc:Back " \
    #     --border-label-pos=bottom \
    #     --prompt='⬇ Buffering ' \
    #     --pointer='➤' \
    #     --header="Streaming: ${title}" \
    #     --header-first \
    #     --color=fg:#f8f8f2,bg:-1,hl:#ff79c6 \
    #     --color=fg+:#ffffff,bg+:#44475a,hl+:#ff79c6 \
    #     --color=info:#bd93f9,prompt:#50fa7b,pointer:#ff79c6 \
    #     --listen "$fzf_port" \
    #     --preview "$preview_script" \
    #     --preview-window=left:55%:wrap:border-right \
    #     --bind='enter:accept' \
    #     --bind='esc:abort' \
    #     --bind='ctrl-c:abort' \
    #     >/dev/null 2>&1
    
    local fzf_exit=$?
    unset preview_script
    
    # Cleanup exports
    unset STAGE2_POSTER STAGE2_TITLE STAGE2_PLOT STAGE2_SOURCES
    
    # If user cancelled, cleanup and return
    if [[ $fzf_exit -ne 0 ]]; then
        cleanup_stream
        if command -v cleanup_on_exit &>/dev/null; then
            trap cleanup_on_exit EXIT INT TERM
        else
            trap - EXIT INT TERM
        fi
        return 1
    fi
    
    # Stream is ready, wait for it to finish
    # Note: Since process is disowned, we loop-wait instead of fg
    if kill -0 "$stream_pid" 2>/dev/null; then
        tput cnorm
        while kill -0 "$stream_pid" 2>/dev/null; do
            sleep 1
        done
    fi
    
    # Cleanup after stream finishes
    cleanup_stream

    # Restore global trap to prevent cleanup_stream firing later with unbound vars
    if command -v cleanup_on_exit &>/dev/null; then
        trap cleanup_on_exit EXIT INT TERM
    else
        trap - EXIT INT TERM
    fi
}
