#!/usr/bin/env bash
#
# Termflix Interactive Season Picker
# usage: season_picker.sh "TITLE" "IMDB_ID"

clear

if [[ "$1" == *"|"* ]]; then
    # Probably raw metadata: index|source|name|...
    TITLE=$(echo "$1" | cut -d'|' -f3)
else
    TITLE="$1"
fi
# Robust IMDB ID extraction: Scan all arguments starting from $2
IMDB_ID=""
shift 1
for arg in "$@"; do
    if [[ "$arg" == tt* ]]; then
        # Check if it looks like a real ID (tt + digits)
        if [[ "$arg" =~ ^tt[0-9]{7,}$ ]]; then
            IMDB_ID="$arg"
            break
        fi
    fi
    # Also check if the argument CONTAINS an imdb id (e.g. inside a combined string)
    if [[ "$arg" =~ tt[0-9]{7,} ]]; then
        IMDB_ID="${BASH_REMATCH[0]}"
        break
    fi
done

# Trace invocation (best-effort, no failure if logging fails)
{
    echo "[$(date)] season_picker invoked"
    echo "  title: $TITLE"
    echo "  imdb : ${IMDB_ID:-<none>}"
    echo "  args : $*"
} >> /tmp/season_picker.log 2>/dev/null

# Resolve directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"
API_DIR="${SCRIPT_DIR}/../api"

# Source modules
[[ -f "${CORE_DIR}/colors.sh" ]] && source "${CORE_DIR}/colors.sh"
[[ -f "${CORE_DIR}/theme.sh" ]] && source "${CORE_DIR}/theme.sh"
[[ -f "${API_DIR}/tmdb.sh" ]] && source "${API_DIR}/tmdb.sh"

# Sanitize input for slug
CLEAN_TITLE=$(echo "$TITLE" | sed -E 's/\[SERIES\]//gi; s/\((19|20)[0-9]{2}\)//g; s/[[:space:]]+(19|20)[0-9]{2}//g; s/[[:space:]]+$//; s/^[[:space:]]+//')
SLUG=$(echo -n "$CLEAN_TITLE" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' | head -c 16)
SEASON_FILE="/tmp/tf_s_${SLUG}"

# Determine current season
CURRENT_SEASON=$(cat "$SEASON_FILE" 2>/dev/null || echo 1)

# Fetch total seasons from TMDB (SILENTLY to preserve background)
if tmdb_configured; then
    metadata_json=""
    if [[ -n "$IMDB_ID" && "$IMDB_ID" != "N/A" ]]; then
        metadata_json=$(find_by_imdb_id "$IMDB_ID" 2>/dev/null)
    else
        metadata_json=$(search_tmdb_tv "$CLEAN_TITLE" "" 2>/dev/null)
    fi
    
    if [[ -n "$metadata_json" ]] && ! echo "$metadata_json" | grep -q '"error"'; then
        tmdb_id=$(echo "$metadata_json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null)
        if [[ -n "$tmdb_id" && "$tmdb_id" != "None" ]]; then
            full_details=$(get_tv_details "$tmdb_id" 2>/dev/null)
            total_seasons=$(echo "$full_details" | python3 -c "import sys, json; print(json.load(sys.stdin).get('number_of_seasons', '1'))" 2>/dev/null)
        fi
    fi
fi

# Fallback to 1 if failed
[[ -z "${total_seasons:-}" ]] && total_seasons=1

echo "[$(date)] total_seasons=$total_seasons" >> /tmp/season_picker.log 2>/dev/null

# Generate Season List for FZF
season_list=""
for ((i=1; i<=total_seasons; i++)); do
    if [[ "$i" == "$CURRENT_SEASON" ]]; then
        season_list+="● Season ${i}\n"
    else
        season_list+="○ Season ${i}\n"
    fi
done

echo "[$(date)] season_list generated: $total_seasons items" >> /tmp/season_picker.log 2>/dev/null

# Show FZF Picker as a centered popup (Clean Simplified Modal)
# Override inherited FZF_DEFAULT_OPTS to avoid catalog shortcuts
export FZF_DEFAULT_OPTS=""

SELECTED=$(printf "$season_list" | fzf \
    --height=70% \
    --margin=15%,20% \
    --layout=reverse \
    --border=rounded \
    --padding=1 \
    --info=inline \
    --prompt="Select Season ➜ " \
    --header="Series: $CLEAN_TITLE (${total_seasons} seasons)" \
    --border-label=" [ Enter:Select | Esc:Back ] " \
    --border-label-pos=bottom \
    --pointer="➜" \
    --color="fg:#ffffff,fg+:#ffffff,hl:${THEME_HEX_GLOW:-#e879f9},hl+:${THEME_HEX_GLOW:-#e879f9},pointer:${THEME_HEX_GLOW:-#e879f9},border:${THEME_HEX_GLOW:-#e879f9},prompt:${THEME_HEX_GLOW:-#e879f9},info:${THEME_HEX_GLOW:-#e879f9},bg+:${THEME_HEX_BG_SELECTION:-#374151}" \
    --bind "esc:abort" \
    --header-first \
    2>>/tmp/season_picker.log)

echo "[$(date)] FZF returned, SELECTED='$SELECTED'" >> /tmp/season_picker.log 2>/dev/null

if [[ -n "$SELECTED" ]]; then
    NEW_SEASON=$(echo "$SELECTED" | grep -oE '[0-9]+')
    if [[ -n "$NEW_SEASON" ]]; then
        echo "$NEW_SEASON" > "$SEASON_FILE"
        echo "$NEW_SEASON" # Output to stdout for caller
        echo "[$(date)] Saved season $NEW_SEASON to $SEASON_FILE" >> /tmp/season_picker.log 2>/dev/null
    fi
fi
