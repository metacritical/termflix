#!/usr/bin/env bash
#
# Termflix Interactive Episode Picker
# usage: episode_picker.sh "TITLE" "IMDB_ID" "SEASON_NUM"
#
# This script handles:
# 1. Fetching episode metadata from TMDB
# 2. Fetching all available EZTV torrents for the show (for availability badges)
# 3. Providing an interactive FZF picker for episodes
# 4. Returning a COMBINED entry for the selected episode to be used by the version picker

TITLE="$1"
IMDB_ID="$2"
SEASON_NUM="${3:-1}"

# Resolve directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CORE_DIR="${UI_DIR}/../core"
API_DIR="${UI_DIR}/../api"
LIB_DIR="${UI_DIR}/lib"

# Source modules
[[ -f "${CORE_DIR}/colors.sh" ]] && source "${CORE_DIR}/colors.sh"
[[ -f "${CORE_DIR}/theme.sh" ]] && source "${CORE_DIR}/theme.sh"
[[ -f "${API_DIR}/tmdb.sh" ]] && source "${API_DIR}/tmdb.sh"

# Sanitize title
CLEAN_TITLE=$(echo "$TITLE" | sed -E 's/\[SERIES\]//gi; s/\((19|20)[0-9]{2}\)//g; s/[[:space:]]+(19|20)[0-9]{2}//g; s/[[:space:]]+$//; s/^[[:space:]]+//')

# 1. Get TMDB Details & Episode List
if ! tmdb_configured; then
    echo -e "${RED}Error: TMDB not configured.${RESET}"
    exit 1
fi

metadata_json=$(find_by_imdb_id "$IMDB_ID" 2>/dev/null)
tmdb_id=$(echo "$metadata_json" | jq -r '.id // empty' 2>/dev/null)
[[ -z "$tmdb_id" ]] && tmdb_id=$(echo "$metadata_json" | jq -r '.movie_results[0].id // empty' 2>/dev/null)
[[ -z "$tmdb_id" ]] && tmdb_id=$(echo "$metadata_json" | jq -r '.tv_results[0].id // empty' 2>/dev/null)

if [[ -z "$tmdb_id" ]]; then
    echo -e "${RED}Error: Could not find TMDB ID for $IMDB_ID${RESET}"
    exit 1
fi

season_details=$(get_tv_season_details "$tmdb_id" "$SEASON_NUM")
episodes_json=$(echo "$season_details" | jq -c '.episodes[]')

# 2. Global EZTV Torrent Fetch
# We fetch ALL torrents for this show from EZTV once.
eztv_cache="/tmp/tf_eztv_${IMDB_ID#tt}.json"
if [[ ! -f "$eztv_cache" ]]; then
    # Try alternate EZTV domains if needed, but for now use primary verify
    curl -s --max-time 10 "https://eztv.yt/api/get-torrents?imdb_id=${IMDB_ID#tt}&limit=100" > "$eztv_cache" 2>/dev/null
fi

# 3. Generate Episode List for FZF
# Get preview percentage from XML template
LAYOUT_XML="${UI_DIR}/layouts/episode-picker.xml"
preview_pct=$(xmllint --xpath "string(//fzf-layout/preview/@size)" "$LAYOUT_XML" 2>/dev/null | tr -d '%')
[[ -z "$preview_pct" || ! "$preview_pct" =~ ^[0-9]+$ ]] && preview_pct=55

# Calculate list width: terminal_width * (100 - preview_pct) / 100
get_term_cols() {
    local cols=""
    cols=$(stty size < /dev/tty 2>/dev/null | awk '{print $2}')
    if [[ -z "$cols" || ! "$cols" =~ ^[0-9]+$ ]]; then
        cols=$(tput cols 2>/dev/null)
    fi
    if [[ -z "$cols" || ! "$cols" =~ ^[0-9]+$ ]]; then
        cols="${COLUMNS:-}"
    fi
    [[ -z "$cols" || ! "$cols" =~ ^[0-9]+$ ]] && cols=100
    echo "$cols"
}
term_cols=$(get_term_cols)
list_width=$(( (term_cols * (100 - preview_pct)) / 100 ))

# Dynamic title width calculation
# Fixed overhead: status(2) + space(1) + ep(3) + " │ "(3) + " │ "(3) + date(width) = 12 + date_width
if [[ $list_width -lt 70 ]]; then
    date_width=6
    date_fmt="+%d %b"
else
    date_width=11
    date_fmt="+%d %b %Y"
fi
FIXED_OVERHEAD=$((12 + date_width))

# Title width = available - fixed overhead
title_max=$((list_width - FIXED_OVERHEAD))
[[ $title_max -lt 10 ]] && title_max=10

today_epoch=$(date +%s)
episode_count=$(echo "$episodes_json" | wc -l | tr -d ' ')
episode_list=""
while read -r e; do
    e_num=$(echo "$e" | jq -r '.episode_number')
    e_name=$(echo "$e" | jq -r '.name // "TBA"')
    e_date=$(echo "$e" | jq -r '.air_date // ""')
    
    # Lock icon for future episodes
    lock_icon="  "
    formatted_date=$(printf "%-${date_width}s" "TBA")
    if [[ -n "$e_date" && "$e_date" != "null" ]]; then
        ep_epoch=$(date -j -f "%Y-%m-%d" "$e_date" +%s 2>/dev/null || date -d "$e_date" +%s 2>/dev/null || echo "0")
        formatted_date=$(date -j -f "%Y-%m-%d" "$e_date" "$date_fmt" 2>/dev/null || date -d "$e_date" "$date_fmt" 2>/dev/null || echo "$e_date")
        formatted_date=$(printf "%-${date_width}s" "$formatted_date")
        [[ "$ep_epoch" -gt "$today_epoch" ]] && lock_icon="🔒"
    fi
    
    # Episode number
    ep_str=$(printf "E%02d" "$e_num")
    
    # Truncate title only if it exceeds column width
    if [[ ${#e_name} -gt $title_max ]]; then
        e_name="${e_name:0:$((title_max-3))}..."
    fi
    
    # Format with proper column widths
    display_line=$(printf "%s %s │ %-${title_max}s │ %s" "$lock_icon" "$ep_str" "$e_name" "$formatted_date")
    
    episode_list+="${e_num}|${display_line}"$'\n'
done <<< "$episodes_json"

# Get Series Poster for rich preview
POSTER_PATH=""
poster_url=$(echo "$metadata_json" | jq -r '.poster_path // .tv_results[0].poster_path // empty' 2>/dev/null)
if [[ -n "$poster_url" && "$poster_url" != "null" ]]; then
    full_poster_url="https://image.tmdb.org/t/p/w500${poster_url}"
    cache_dir="${HOME}/.cache/termflix/posters"; mkdir -p "$cache_dir"
    hash=$(echo -n "$full_poster_url" | python3 -c "import sys,hashlib;print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
    POSTER_PATH="${cache_dir}/${hash}.png"
    [[ ! -f "$POSTER_PATH" ]] && curl -sL --max-time 5 "$full_poster_url" -o "$POSTER_PATH" 2>/dev/null
fi

# 4. Interactive FZF Stage
export SEASON_DETAILS="$season_details"
export EZTV_CACHE="$eztv_cache"
export SERIES_POSTER="$POSTER_PATH"
export S_NUM="$SEASON_NUM"

# Source display helper for preview
source "${LIB_DIR}/image_display.sh"

# Export additional series metadata for preview
export SERIES_METADATA="$metadata_json"

# ════════════════════════════════════════════════════════════════
# TML Parser Integration
# ════════════════════════════════════════════════════════════════
export CLEAN_TITLE
export SEASON_NUM
export SCRIPT_DIR

source "${UI_DIR}/tml/parser/tml_parser.sh"
tml_parse "${UI_DIR}/layouts/episode-picker.xml"
RESULTS=$(printf '%s' "$episode_list" | tml_run_fzf --ansi)

# ════════════════════════════════════════════════════════════════
# OLD HARDCODED FZF CONFIG (preserved for reference)
# ════════════════════════════════════════════════════════════════
# RESULTS=$(printf '%s' "$episode_list" | fzf \
#     --height=100% \
#     --layout=reverse \
#     --border=rounded \
#     --margin=1 \
#     --padding=1 \
#     --delimiter='|' \
#     --with-nth=2 \
#     --pointer='➤' \
#     --prompt="> " \
#     --header="Pick Episode - [$CLEAN_TITLE] Season ${SEASON_NUM} →" \
#     --header-first \
#     --info=default \
#     --border-label=" ⌨ Enter:Select  Ctrl+E:Season  Ctrl+H:Back " \
#     --border-label-pos=bottom \
#     --expect=enter,ctrl-e,ctrl-s,ctrl-h,ctrl-l,esc \
#     --ansi \
#     --color="$(get_fzf_colors 2>/dev/null || echo 'fg:#cdd6f4,bg:-1,hl:#f5c2e7,fg+:#cdd6f4,bg+:#5865f2,hl+:#f5c2e7,pointer:#f5c2e7,prompt:#cba6f7')" \
#     --preview-window=left:55%:wrap:border-right \
#     --preview "ep_no=\$(echo {} | cut -d'|' -f1); ${SCRIPT_DIR}/preview_episode.sh \"\$ep_no\"")

KEY=$(echo "$RESULTS" | head -1)
SELECTED=$(echo "$RESULTS" | tail -1)

# Cleanup
[[ "$TERM" == "xterm-kitty" ]] && kitten icat --clear >/dev/null 2>&1

if [[ -z "$KEY" ]]; then
    exit 0 # Back
fi

case "$KEY" in
    ctrl-e|ctrl-s)
        echo "SWITCH_SEASON"
        ;;
    ctrl-h|esc)
        # explicitly signal back
        echo "BACK"
        ;;
    enter|ctrl-l)
        if [[ -n "$SELECTED" ]]; then
            E_NUM=$(echo "$SELECTED" | cut -d'|' -f1)
            echo "SELECTED_EPISODE|$E_NUM"
        fi
        ;;
esac
