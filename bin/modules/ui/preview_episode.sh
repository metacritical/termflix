#!/usr/bin/env bash
#
# Episode Preview Script - Matches Movies Stage 2 Layout
# -------------------------------------------------------
# Used in Shows Stage 2 (Episode Picker) preview pane.
# Provides the same large poster + metadata layout as Movies.
#

# Resolve script location
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR_TMP="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR_TMP/$SCRIPT_SOURCE"
done
_SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"

# Source dependencies
source "${_SCRIPT_DIR}/../core/colors.sh"
[[ -f "${_SCRIPT_DIR}/../core/theme.sh" ]] && source "${_SCRIPT_DIR}/../core/theme.sh"
[[ -f "${_SCRIPT_DIR}/image_display.sh" ]] && source "${_SCRIPT_DIR}/image_display.sh"

# Alias semantic colors
MAGENTA="${THEME_GLOW:-${C_GLOW}}"
CYAN="${THEME_INFO:-${C_INFO}}"
GRAY="${THEME_FG_MUTED:-${C_MUTED}}"
GREEN="${THEME_SUCCESS:-${C_SUCCESS}}"
YELLOW="${THEME_WARNING:-${C_WARNING}}"
PURPLE="${THEME_PURPLE:-${C_PURPLE}}"
BOLD=$(printf "\033[1m")
RESET=$(printf "\033[0m")

# Get episode data from environment (exported by episode_picker.sh)
ep_no="$1"
e_info=$(echo "$SEASON_DETAILS" | jq -c --argjson n "$ep_no" '.episodes[] | select(.episode_number == $n)' 2>/dev/null)
e_name=$(echo "$e_info" | jq -r '.name // "Episode"')
e_plot=$(echo "$e_info" | jq -r '.overview // "No description available."')
e_rating=$(echo "$e_info" | jq -r '.vote_average // "N/A"')
e_date=$(echo "$e_info" | jq -r '.air_date // "TBA"')
e_runtime=$(echo "$e_info" | jq -r '.runtime // 45')

# Series-level metadata
s_genres=$(echo "$SERIES_METADATA" | jq -r '[.genres[]?.name] | join(", ") // "Drama"' 2>/dev/null)
[[ -z "$s_genres" || "$s_genres" == "null" ]] && s_genres="Drama"
s_title=$(echo "$SERIES_METADATA" | jq -r '.name // .title // "Unknown Series"' 2>/dev/null)
s_year=$(echo "$SERIES_METADATA" | jq -r '.first_air_date // ""' 2>/dev/null)
s_year="${s_year:0:4}"

# ═══════════════════════════════════════════════════════════════
# HEADER - Episode Title (no results count header)
# ═══════════════════════════════════════════════════════════════

# Episode title
echo -e "${BOLD}${MAGENTA}${e_name}${RESET}"
echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

# ═══════════════════════════════════════════════════════════════
# METADATA - Sources, Runtime, Rating
# ═══════════════════════════════════════════════════════════════

# Sources (show available sources for this episode from EZTV cache)
if [[ -f "$EZTV_CACHE" ]]; then
    torrent_count=$(jq -r --argjson ep "$ep_no" --argjson s "${S_NUM:-1}" '.torrents[]? | select(.season == ($s | tostring) and .episode == ($ep | tostring)) | .hash' "$EZTV_CACHE" 2>/dev/null | wc -l | tr -d ' ')
    [[ "$torrent_count" -gt 0 ]] && echo -e "${BOLD}Sources:${RESET} ${GREEN}[EZTV]${RESET} - ${torrent_count} 🧲"
fi

# Combine runtime, year, rating
meta_line=""
[[ "$e_runtime" != "null" && -n "$e_runtime" ]] && meta_line+="${e_runtime} min    "
[[ "$e_date" != "TBA" && "$e_date" != "null" ]] && meta_line+="${e_date}    "
if [[ "$e_rating" != "N/A" && "$e_rating" != "0" && "$e_rating" != "null" ]]; then
    meta_line+="⭐ $(printf "%.1f" "$e_rating")"
fi
[[ -n "$meta_line" ]] && echo -e "${BOLD}Available:${RESET} ${CYAN}${meta_line}${RESET}"
echo

echo -e "${GRAY}Ctrl+H to go back • Enter to select${RESET}"
echo -e "${GRAY}────────────────────────────────────────${RESET}"

# ═══════════════════════════════════════════════════════════════
# POSTER - Large like Movies Stage 2
# ═══════════════════════════════════════════════════════════════

poster_file="$SERIES_POSTER"

IS_KITTY_MODE=false
if [[ "$TERM" == "xterm-kitty" ]] && command -v kitten &> /dev/null; then
    IS_KITTY_MODE=true
fi

if [[ "$IS_KITTY_MODE" == "true" ]]; then
    # KITTY MODE: Large poster with absolute positioning
    FALLBACK_IMG="${_SCRIPT_DIR%/bin/modules/ui}/lib/torrent/img/movie_night.jpg"
    [[ -z "$poster_file" || ! -f "$poster_file" ]] && poster_file="$FALLBACK_IMG"
    
    if [[ -f "$poster_file" ]]; then
        IMAGE_WIDTH=40
        IMAGE_HEIGHT=30
        
        kitten icat --transfer-mode=file --stdin=no \
            --place=${IMAGE_WIDTH}x${IMAGE_HEIGHT}@0x0 \
            --scale-up --align=left \
            "$poster_file" 2>/dev/null
    fi
    echo
else
    # BLOCK MODE: Use viu/chafa
    if [[ -n "$poster_file" && -f "$poster_file" ]]; then
        if command -v viu &>/dev/null; then
            viu -w 50 -h 35 "$poster_file" 2>/dev/null
        elif command -v chafa &>/dev/null; then
            chafa --size=50x35 "$poster_file" 2>/dev/null
        fi
        echo
    fi
fi

# ═══════════════════════════════════════════════════════════════
# DESCRIPTION & GENRE
# ═══════════════════════════════════════════════════════════════

# Plot/Summary - print color, then text (fmt can't handle ANSI codes)
if [[ -n "$e_plot" && "$e_plot" != "No description available." ]]; then
    printf "%s" "$GRAY"
    echo "$e_plot" | fmt -w 50
    printf "%s" "$RESET"
    echo
fi

# Genre footer
echo -e "${s_genres}"
