#!/usr/bin/env bash
#
# Stage 2 Preview Script - UNIFIED (Kitty + Block Mode)
# ---------------------------------------------------
# Used as the LEFT preview pane when picking a version.
# It renders a static copy of the movie catalog list so that
# Stage 2 appears visually identical to Stage 1, while the
# actual FZF picker (versions) lives on the right.
#
# Supports both Kitty terminal (with absolute positioning) and
# standard terminals (block mode with viu/chafa).
#

# Resolve script location for sourcing dependencies
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR_TMP="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR_TMP/$SCRIPT_SOURCE"
done
_SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"

# Source dependencies
source "${_SCRIPT_DIR}/../core/colors.sh"
source "${_SCRIPT_DIR}/image_display.sh"

# Optionally source theme for enhanced colors
[[ -f "${_SCRIPT_DIR}/../core/theme.sh" ]] && source "${_SCRIPT_DIR}/../core/theme.sh"

# Alias semantic colors for this script
MAGENTA="${THEME_GLOW:-${C_GLOW}}"
CYAN="${THEME_INFO:-${C_INFO}}"
GRAY="${THEME_FG_MUTED:-${C_MUTED}}"
GREEN="${THEME_SUCCESS:-${C_SUCCESS}}"
YELLOW="${THEME_WARNING:-${C_WARNING}}"
PURPLE="${THEME_PURPLE:-${C_PURPLE}}"

# Get environment variables set by fzf_catalog.sh
selected_index="${STAGE2_SELECTED_INDEX:-}"
title="${STAGE2_TITLE:-Unknown Title}"
poster_file="${STAGE2_POSTER:-}"
sources="${STAGE2_SOURCES:-}"
avail="${STAGE2_AVAIL:-}"
plot="${STAGE2_PLOT:-}"
imdb="${STAGE2_IMDB:-}"

# Try environment first, otherwise fall back to snapshot files
header="${TERMFLIX_LAST_FZF_HEADER:-}"
catalog="${TERMFLIX_LAST_FZF_DISPLAY:-}"

if [[ -z "$header" ]]; then
    snap_dir="${TMPDIR:-/tmp}"
    snap_header_file="${snap_dir}/termflix_stage1_fzf_header.txt"
    [[ -f "$snap_header_file" ]] && header="$(cat "$snap_header_file" 2>/dev/null)"
fi

if [[ -z "$catalog" ]]; then
    snap_dir="${TMPDIR:-/tmp}"
    snap_file="${snap_dir}/termflix_stage1_fzf_display.txt"
    [[ -f "$snap_file" ]] && catalog="$(cat "$snap_file" 2>/dev/null)"
fi

# ═══════════════════════════════════════════════════════════════
# DISPLAY MODE DETECTION
# ═══════════════════════════════════════════════════════════════

IS_KITTY_MODE=false
if [[ "$TERM" == "xterm-kitty" ]] && command -v kitten &> /dev/null; then
    IS_KITTY_MODE=true
fi

# ═══════════════════════════════════════════════════════════════
# HEADER AND CATALOG RENDERING
# ═══════════════════════════════════════════════════════════════

# Render header (matches Stage 1 style)
if [[ -n "$header" ]]; then
    echo -e "${BOLD}${CYAN}${header}${RESET}"
    echo
fi

# Render catalog snapshot if available
if [[ -z "$catalog" ]]; then
    echo -e "${DIM}No catalog snapshot available for Stage 2 preview.${RESET}"
else
    # Re-render the movie list with selection marker
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        IFS='|' read -r display idx _ <<< "$line"
        
        if [[ -n "$selected_index" && "$idx" == "$selected_index" ]]; then
            # Highlight the originally selected movie
            echo -e "${MAGENTA}▶ ${BOLD}${display}${RESET}"
        else
            echo "  $display"
        fi
    done <<< "$catalog"
fi

# Footer separator
echo
echo -e "${GRAY}────────────────────────────────────────${RESET}"

# ═══════════════════════════════════════════════════════════════
# BUFFERING STATUS (if streaming is active)
# ═══════════════════════════════════════════════════════════════

BUFFER_STATUS_FILE="/tmp/termflix_buffer_status.txt"

if [[ -f "$BUFFER_STATUS_FILE" ]]; then
    # Source buffer UI module
    BUFFER_UI="${_SCRIPT_DIR}/../streaming/buffer_ui.sh"
    [[ -f "$BUFFER_UI" ]] && source "$BUFFER_UI"
    
    IFS='|' read -r b_percent b_speed b_peers_conn b_peers_total b_size b_status < "$BUFFER_STATUS_FILE"
    
    if [[ "$b_status" == "BUFFERING" ]]; then
        echo -e "${BOLD}${CYAN}⏳ Buffering...${RESET}"
        if type draw_line_bar &> /dev/null; then
            echo -e "$(draw_line_bar "${b_percent:-0}" 35)  ${b_percent:-0}%"
        else
            echo -e "Progress: ${b_percent:-0}%"
        fi
        [[ -n "$b_speed" && "$b_speed" != "0" ]] && echo -e "Down: ${b_speed} KB/s"
        echo -e "${DIM}Press Ctrl+C to cancel${RESET}"
    elif [[ "$b_status" == "READY" ]]; then
        echo -e "${BOLD}${GREEN}✓ Buffer ready!${RESET}"
    elif [[ "$b_status" == "PLAYING" ]]; then
        echo -e "${BOLD}${GREEN}▶ Now playing${RESET}"
    fi
else
    # Show metadata if not streaming
    if [[ "$IS_KITTY_MODE" == "false" ]]; then
        # Block mode: Show metadata before poster
        echo -e "${BOLD}${MAGENTA}${title}${RESET}"
        echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo
        
        [[ -n "$sources" ]] && echo -e "${BOLD}Sources:${RESET} ${GREEN}${sources}${RESET}"
        [[ -n "$avail" ]] && echo -e "${BOLD}Available:${RESET} ${CYAN}${avail}${RESET}"
        [[ -n "$imdb" && "$imdb" != "N/A" ]] && echo -e "${BOLD}IMDB:${RESET} ${YELLOW}⭐ ${imdb}${RESET}"
        echo
    fi
    
    echo -e "${DIM}Ctrl+H to go back • Enter to stream${RESET}"
fi

# ═══════════════════════════════════════════════════════════════
# POSTER RENDERING
# ═══════════════════════════════════════════════════════════════

if [[ "$IS_KITTY_MODE" == "true" ]]; then
    # KITTY MODE: Use absolute positioning to keep poster on right side
    # This maintains the Stage 1 visual layout
    
    # Resolve fallback image path
    FALLBACK_IMG="${_SCRIPT_DIR%/bin/modules/ui}/lib/torrent/img/movie_night.jpg"
    [[ -z "$poster_file" || ! -f "$poster_file" ]] && poster_file="$FALLBACK_IMG"
    
    if [[ -f "$poster_file" ]]; then
        cols=$(tput cols 2>/dev/null || echo 120)
        preview_cols="${FZF_PREVIEW_COLUMNS:-$cols}"
        
        IMAGE_WIDTH=20
        IMAGE_HEIGHT=15
        
        # Compute X offset where Stage 1's preview pane would start
        # In Stage 2, the preview window is on the LEFT, so the right FZF list
        # starts at column preview_cols
        start_x=$preview_cols
        (( start_x < 0 )) && start_x=0
        
        # Draw poster at the calculated position (row 2 of right pane)
        kitten icat --transfer-mode=file --stdin=no \
            --place=${IMAGE_WIDTH}x${IMAGE_HEIGHT}@${start_x}x2 \
            --scale-up --align=left \
            "$poster_file" 2>/dev/null
    fi
else
    # BLOCK MODE: Use universal image display helper
    # Image flows naturally in the text stream
    
    if [[ -n "$poster_file" && -f "$poster_file" ]]; then
        display_image "$poster_file" 50 35
    else
        # Try to download poster if we have a cached URL
        cache_dir="${HOME}/.cache/termflix/posters"
        
        if [[ -n "$title" && "$title" != "Unknown Title" ]]; then
            # Compute title hash for cache lookup
            title_hash=$(echo -n "$title" | tr '[:upper:]' '[:lower:]' | python3 -c "import sys,hashlib;print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
            
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
                        display_image "$poster_file" 50 35
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
    
    # Display plot in block mode
    if [[ -n "$plot" && "$plot" != "N/A" ]]; then
        echo -e "${DIM}${plot}${RESET}"
        echo
    fi
fi
