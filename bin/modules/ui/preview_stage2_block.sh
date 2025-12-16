#!/usr/bin/env bash
#
# Stage 2 Preview Script for BLOCK TEXT Mode (xterm-256color)
# Shows: Large Poster + Title + Basic Info
#
# Uses environment variables set by fzf_catalog.sh:
#   STAGE2_POSTER, STAGE2_TITLE, STAGE2_SOURCES, STAGE2_AVAIL, STAGE2_PLOT, STAGE2_IMDB
#

# --- 1. Resolve Script Directory ---
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR_TMP="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR_TMP/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"

# --- 2. Source Theme & Colors ---
if [[ -f "${SCRIPT_DIR}/../core/theme.sh" ]]; then
    source "${SCRIPT_DIR}/../core/theme.sh"
fi
source "${SCRIPT_DIR}/../core/colors.sh"

# Use theme colors with fallback
MAGENTA="${THEME_GLOW:-$C_GLOW}"
GREEN="${THEME_SUCCESS:-$C_SUCCESS}"
CYAN="${THEME_INFO:-$C_INFO}"
YELLOW="${THEME_WARNING:-$C_WARNING}"
GRAY="${THEME_FG_MUTED:-$C_MUTED}"
PURPLE="${THEME_PURPLE:-$C_PURPLE}"

# --- 3. Get Data from Environment Variables ---
title="${STAGE2_TITLE:-Unknown Title}"
poster_file="${STAGE2_POSTER:-}"
sources="${STAGE2_SOURCES:-}"
avail="${STAGE2_AVAIL:-}"
plot="${STAGE2_PLOT:-}"
imdb="${STAGE2_IMDB:-}"

# --- 4. Display Title Header ---
echo -e "${BOLD}${MAGENTA}${title}${RESET}"
echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

# --- 5. Display Metadata ---
[[ -n "$sources" ]] && echo -e "${BOLD}Sources:${RESET} ${GREEN}${sources}${RESET}"
[[ -n "$avail" ]] && echo -e "${BOLD}Available:${RESET} ${CYAN}${avail}${RESET}"
[[ -n "$imdb" && "$imdb" != "N/A" ]] && echo -e "${BOLD}IMDB:${RESET} ${YELLOW}⭐ ${imdb}${RESET}"
echo

# --- 6. Display Poster ---
# First check if poster file exists
if [[ -n "$poster_file" && -f "$poster_file" && -s "$poster_file" ]]; then
    # Display poster using viu block graphics
    if command -v viu &>/dev/null; then
        TERM=xterm-256color viu -w 50 -h 35 "$poster_file" 2>/dev/null
    elif command -v chafa &>/dev/null; then
        TERM=xterm-256color chafa --symbols=block --size="50x35" "$poster_file" 2>/dev/null
    fi
else
    # Try to download poster if we have a URL in cache
    cache_dir="${HOME}/.cache/termflix/posters"
    
    # Try to find any cached poster for this title
    if [[ -n "$title" && "$title" != "Unknown Title" ]]; then
        # Compute title hash
        title_hash=$(echo -n "$title" | tr '[:upper:]' '[:lower:]' | python3 -c "import sys,hashlib;print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
        
        # Check for search cache URL
        search_cache="${cache_dir}/search_${title_hash}.url"
        if [[ -f "$search_cache" ]]; then
            cached_url=$(cat "$search_cache")
            if [[ -n "$cached_url" && "$cached_url" != "null" && "$cached_url" != "N/A" ]]; then
                url_hash=$(echo -n "$cached_url" | python3 -c "import sys,hashlib;print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
                poster_file="${cache_dir}/${url_hash}.png"
                
                # Download if not exists
                if [[ ! -f "$poster_file" ]]; then
                    curl -sL --max-time 3 "$cached_url" -o "$poster_file" 2>/dev/null
                fi
                
                # Display if we got it
                if [[ -f "$poster_file" && -s "$poster_file" ]]; then
                    if command -v viu &>/dev/null; then
                        TERM=xterm-256color viu -w 50 -h 35 "$poster_file" 2>/dev/null
                    elif command -v chafa &>/dev/null; then
                        TERM=xterm-256color chafa --symbols=block --size="50x35" "$poster_file" 2>/dev/null
                    fi
                else
                    echo -e "${DIM}[Fetching poster...]${RESET}"
                fi
            else
                echo -e "${DIM}[No poster available]${RESET}"
            fi
        else
            echo -e "${DIM}[No poster cached]${RESET}"
        fi
    else
        echo -e "${DIM}[No title info]${RESET}"
    fi
fi

echo
# --- 7. Display Plot ---
if [[ -n "$plot" && "$plot" != "N/A" ]]; then
    echo -e "${DIM}${plot}${RESET}"
    echo
fi

# --- 8. Display Buffering Status (if streaming is active) ---
BUFFER_STATUS_FILE="/tmp/termflix_buffer_status.txt"

if [[ -f "$BUFFER_STATUS_FILE" ]]; then
    # Source buffer UI module for progress bar rendering
    BUFFER_UI="${SCRIPT_DIR}/../streaming/buffer_ui.sh"
    [[ -f "$BUFFER_UI" ]] && source "$BUFFER_UI"
    
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
    
    # Read status from file (format: PERCENT|SPEED|PEERS_CONN|PEERS_TOTAL|SIZE_MB|STATUS)
    IFS='|' read -r b_percent b_speed b_peers_conn b_peers_total b_size b_status < "$BUFFER_STATUS_FILE"
    
    if [[ "$b_status" == "BUFFERING" ]]; then
        echo -e "${BOLD}${CYAN}⏳ Buffering...${RESET}"
        
        # Draw progress bar
        if type draw_line_bar &>/dev/null; then
            echo -e "$(draw_line_bar "${b_percent:-0}" 35)  ${b_percent:-0}%"
        else
            # Fallback: simple percent display
            echo -e "${CYAN}Progress:${RESET} ${b_percent:-0}%"
        fi
        
        # Show stats if available
        [[ -n "$b_speed" && "$b_speed" != "0" ]] && echo -e "Down: ${b_speed} KB/s"
        [[ -n "$b_peers_total" && "$b_peers_total" != "0" ]] && echo -e "Peers: ${b_peers_conn:-0}/${b_peers_total}"
        [[ -n "$b_size" ]] && echo -e "Downloaded: ${b_size} MB"
        
        echo
        echo -e "${DIM}Press Ctrl+C to cancel${RESET}"
    elif [[ "$b_status" == "READY" ]]; then
        echo -e "${BOLD}${GREEN}✓ Buffer ready! Launching player...${RESET}"
    elif [[ "$b_status" == "PLAYING" ]]; then
        echo -e "${BOLD}${GREEN}▶ Now playing in external player${RESET}"
    fi
else
    echo -e "${DIM}Select a version from the picker →${RESET}"
fi

