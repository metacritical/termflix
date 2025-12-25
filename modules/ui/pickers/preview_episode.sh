#!/usr/bin/env bash
#
# Episode Preview Script - Matches Movies Stage 2 Layout
# -------------------------------------------------------
# Used in Shows Stage 2 (Episode Picker) preview pane.
# Layout: Title → Sources → Available → [Poster] → Description → Genre
#

# Resolve script location
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR_TMP="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR_TMP/$SCRIPT_SOURCE"
done
_SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
UI_DIR="$(cd "${_SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${UI_DIR}/../.." && pwd)"

# Source dependencies
source "${UI_DIR}/../core/colors.sh"
[[ -f "${UI_DIR}/../core/theme.sh" ]] && source "${UI_DIR}/../core/theme.sh"
[[ -f "${UI_DIR}/../core/genres.sh" ]] && source "${UI_DIR}/../core/genres.sh"

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

# Check Kitty mode
IS_KITTY_MODE=false
if [[ "$TERM" == "xterm-kitty" ]] && command -v kitten &> /dev/null; then
    IS_KITTY_MODE=true
fi

# ═══════════════════════════════════════════════════════════════
# 1. HEADER - Title (FIRST)
# ═══════════════════════════════════════════════════════════════

echo -e "📺  ${BOLD}${MAGENTA}${e_name}${RESET}"
echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

# ═══════════════════════════════════════════════════════════════
# 2. METADATA - Sources, Runtime, Rating
# ═══════════════════════════════════════════════════════════════

# Sources (show available sources for this episode from EZTV cache)
EZTV_CACHE="${TMPDIR:-/tmp}/termflix_eztv_cache.json"
if [[ -f "$EZTV_CACHE" ]]; then
    S_NUM="${S_NUM:-1}"
    torrent_count=$(jq -r --argjson ep "$ep_no" --argjson s "${S_NUM}" '.torrents[]? | select(.season == ($s | tostring) and .episode == ($ep | tostring)) | .hash' "$EZTV_CACHE" 2>/dev/null | wc -l | tr -d ' ')
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

# ═══════════════════════════════════════════════════════════════
# 3. POSTER - After metadata
# ═══════════════════════════════════════════════════════════════

poster_file="$SERIES_POSTER"
FALLBACK_IMG="${ROOT_DIR}/lib/torrent/img/movie_night.jpg"
[[ -z "$poster_file" || ! -f "$poster_file" ]] && poster_file="$FALLBACK_IMG"

if [[ "$IS_KITTY_MODE" == "true" ]]; then
    # KITTY MODE: Poster size (50x30)
    KITTY_WIDTH=50
    KITTY_HEIGHT=30
    
    if [[ -f "$poster_file" ]]; then
        kitten icat --transfer-mode=file --stdin=no \
            --place=${KITTY_WIDTH}x${KITTY_HEIGHT}@0x4 \
            --scale-up --align=left \
            "$poster_file" 2>/dev/null
        # Add newlines to push cursor below image
        for ((i=0; i<KITTY_HEIGHT; i++)); do echo; done
    fi
else
    # BLOCK MODE: Poster size (40x30)
    if [[ -n "$poster_file" && -f "$poster_file" ]]; then
        if command -v viu &>/dev/null; then
            viu -w 40 -h 30 "$poster_file" 2>/dev/null
        elif command -v chafa &>/dev/null; then
            chafa --size=40x30 "$poster_file" 2>/dev/null
        fi
        echo
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 4. METADATA AFTER POSTER - Rating, Release Date, Genre
# ═══════════════════════════════════════════════════════════════

echo  # Line after poster

# Rating
if [[ "$e_rating" != "N/A" && "$e_rating" != "0" && "$e_rating" != "null" && -n "$e_rating" ]]; then
    echo -e "${BOLD}Rating:${RESET} ${YELLOW}⭐ $(printf "%.1f" "$e_rating")${RESET}"
fi

# Release Date
if [[ "$e_date" != "TBA" && "$e_date" != "null" && -n "$e_date" ]]; then
    echo -e "${BOLD}Release Date:${RESET} ${CYAN}${e_date}${RESET}"
fi

# Genre (moved from bottom)
if [[ -n "$s_genres" && "$s_genres" != "null" ]]; then
    if command -v style_genres &>/dev/null; then
        styled_genre=$(style_genres "$s_genres" 2>/dev/null || echo "$s_genres")
        echo -e "${BOLD}Genre:${RESET} ${styled_genre}\033[K"
    else
        echo -e "${BOLD}Genre:${RESET} ${s_genres}"
    fi
fi

echo  # Line before description

# ═══════════════════════════════════════════════════════════════
# 5. DESCRIPTION
# ═══════════════════════════════════════════════════════════════

# Plot/Summary
if [[ -n "$e_plot" && "$e_plot" != "No description available." && "$e_plot" != "null" ]]; then
    printf "%s" "$GRAY"
    echo "$e_plot" | fmt -w 50
    printf "%s" "$RESET"
    echo
fi

# ═══════════════════════════════════════════════════════════════
# 6. SHORTCUTS FOOTER
# ═══════════════════════════════════════════════════════════════

echo -e "${GRAY}Ctrl+H to go back • Enter to select${RESET}"
