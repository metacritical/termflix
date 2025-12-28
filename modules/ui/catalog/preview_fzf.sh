#!/usr/bin/env bash
#
# Termflix FZF Preview Script - Stremio Style
# Renders comprehensive movie details with poster, description, and magnet picker
#

# --- 1. Parse Input ---
# FZF passes {3..} which is everything from field 3 onward
# Format received: "Source|Title|RestOfData..."
input_line="$1"
[[ -z "$input_line" ]] && exit 0

# Preview gets closed often; ignore SIGPIPE to avoid noisy errors.
trap '' PIPE

# Resolve Script Directory (always resolve, needed for module paths)
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
# Follow symlinks if any
while [ -L "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR_TMP="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR_TMP/$SCRIPT_SOURCE"
done
# Always set SCRIPT_DIR after resolving symlinks
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
UI_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${UI_DIR}/../.." && pwd)"

if [[ -z "$TERMFLIX_SCRIPTS_DIR" ]]; then
    TERMFLIX_SCRIPTS_DIR="$(cd "${ROOT_DIR}/lib/termflix/scripts" 2>/dev/null && pwd)"
fi

# --- 2. Source Theme & Colors ---
if [[ -f "${UI_DIR}/../core/theme.sh" ]]; then
    source "${UI_DIR}/../core/theme.sh"
fi
source "${UI_DIR}/../core/colors.sh"
[[ -f "${UI_DIR}/../core/genres.sh" ]] && source "${UI_DIR}/../core/genres.sh"
[[ -f "${UI_DIR}/../core/languages.sh" ]] && source "${UI_DIR}/../core/languages.sh"

# Alias semantic colors (with theme fallback)
MAGENTA="${THEME_GLOW:-$C_GLOW}"
GREEN="${THEME_SUCCESS:-$C_SUCCESS}"
CYAN="${THEME_INFO:-$C_INFO}"
YELLOW="${THEME_WARNING:-$C_WARNING}"
BLUE="${THEME_INFO:-$C_INFO}"
GRAY="${THEME_FG_MUTED:-$C_MUTED}"
ORANGE="${THEME_ORANGE:-$C_ORANGE}"
PURPLE="${THEME_PURPLE:-$C_PURPLE}"

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

get_preview_cols() {
    local cols="${FZF_PREVIEW_COLUMNS:-}"
    if [[ -n "$cols" && "$cols" =~ ^[0-9]+$ && "$cols" -ge 20 ]]; then
        echo "$cols"
        return
    fi
    local term_cols
    term_cols=$(get_term_cols)
    local layout_file="${UI_DIR}/layouts/main-catalog.tml"
    local preview_pct
    preview_pct=$(xmllint --xpath "string(//preview/@size)" "$layout_file" 2>/dev/null | tr -d '%')
    [[ -z "$preview_pct" || ! "$preview_pct" =~ ^[0-9]+$ ]] && preview_pct=50
    cols=$(( (term_cols * preview_pct) / 100 ))
    [[ "$cols" -lt 20 ]] && cols=60
    echo "$cols"
}

# --- 3. Parse Input ---
# Format: index|Source|Title|RestOfData... (after TAB delimiter change)
# Skip the index field and parse the rest
idx_field=""
actual_data=""
IFS='|' read -r idx_field actual_data <<< "$input_line"
IFS='|' read -r source title rest <<< "$actual_data"

# --- 4. Identify Type & Sanitize ---
is_series="false"
# Check both local and exported category variables
cat_lower=$(echo "${current_category:-${CURRENT_CATEGORY:-}}" | tr '[:upper:]' '[:lower:]')
[[ "$cat_lower" == "shows" || "$cat_lower" == "tv" ]] && is_series="true"
[[ "$title" == *"[SERIES]"* ]] && is_series="true"

# Extract Year and Clean Title for API
movie_year=""
if [[ "$title" =~ (19[0-9]{2}|20[0-9]{2}) ]]; then
    movie_year="${BASH_REMATCH[1]}"
fi
# Clean title for API lookups - remove all quality markers, brackets, codec info
clean_title_for_api="$title"
# Remove bracketed content like [1080p], [WEBRip], [5.1], [SERIES]
clean_title_for_api=$(echo "$clean_title_for_api" | sed -E 's/\[[^]]*\]//g')
# Remove quality/codec markers
clean_title_for_api=$(echo "$clean_title_for_api" | sed -E 's/[[:space:]]+(1080p|720p|480p|2160p|4K|HDRip|BRRip|BluRay|WEB-DL|WEBRip|HDTV|x264|x265|HEVC|AAC|DTS|10bit|HDR|REMUX)([[:space:]]|$)/ /gi')
# Remove release group at end (e.g., -YTS, -RARBG)
clean_title_for_api=$(echo "$clean_title_for_api" | sed -E 's/[[:space:]]*-[A-Za-z0-9]+$//')
# Remove year (we add it back separately if needed)
clean_title_for_api=$(echo "$clean_title_for_api" | sed -E 's/\((19|20)[0-9]{2}\)//g; s/[[:space:]]+(19|20)[0-9]{2}//g')
# Trim whitespace
clean_title_for_api=$(echo "$clean_title_for_api" | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')


# Sanitize display title
display_title="$title"
display_title="${display_title% [SERIES]}"

# Define API Modules
TMDB_MODULE="${UI_DIR}/../api/tmdb.sh"
OMDB_MODULE="${UI_DIR}/../api/omdb.sh"

# --- 5. Logic & Data Fetching ---
# Initialize metadata variables
movie_rating="N/A"
movie_genre=""
description=""
poster_url=""
imdb_id=""
total_seasons=""
latest_season_num=""
episodes_list_raw=""
movie_language=""
preview_cols="$(get_preview_cols)"

# Season Persistence (Stage 1)
# Title-based hash to remember season selection per show (legacy fallback)
title_slug=$(echo -n "$clean_title_for_api" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' | head -c 16)

if [[ "$source" == "COMBINED" ]]; then
    # COMBINED format: source|title|sources|qualities|seeds|sizes|magnets|poster|imdb|genre|count
    IFS='|' read -r sources qualities seeds sizes magnets poster_url current_imdb_id genre_text torrent_count <<< "$rest"
    imdb_id="$current_imdb_id"
    movie_genre="$genre_text"
    # Note: COMBINED doesn't currently carry rating, but we can fetch it via TMDB/OMDB if we have imdb_id
else
    magnet=$(echo "$rest" | cut -d'|' -f1)
    quality=$(echo "$rest" | cut -d'|' -f2)
    size=$(echo "$rest" | cut -d'|' -f3)
    seeds=$(echo "$rest" | cut -d'|' -f4)
    poster_url=$(echo "$rest" | cut -d'|' -f5)
    imdb_id=$(echo "$rest" | cut -d'|' -f6)
    [[ "$imdb_id" == tt* ]] || imdb_id=""
fi

# Prefer IMDB-based season key when available; fallback to title slug.
season_file_legacy="/tmp/tf_s_${title_slug}"
season_file=""
if [[ -n "$imdb_id" ]]; then
    season_file="/tmp/tf_s_${imdb_id#tt}"
    if [[ -f "$season_file" ]]; then
        selected_preview_season=$(cat "$season_file" 2>/dev/null || echo "")
    else
        selected_preview_season=$(cat "$season_file_legacy" 2>/dev/null || echo "")
    fi
else
    season_file="$season_file_legacy"
    selected_preview_season=$(cat "$season_file" 2>/dev/null || echo "")
fi

# Fetch Rich Metadata
if [[ -f "$TMDB_MODULE" ]]; then
    source "$TMDB_MODULE"
    if tmdb_configured; then
        if [[ -n "$imdb_id" && "$imdb_id" != "N/A" ]]; then
            metadata_json=$(find_by_imdb_id "$imdb_id" 2>/dev/null)
        else
            if [[ "$is_series" == "true" ]]; then
                metadata_json=$(search_tmdb_tv "$clean_title_for_api" "$movie_year" 2>/dev/null)
            else
                metadata_json=$(search_tmdb_movie "$clean_title_for_api" "$movie_year" 2>/dev/null)
            fi
        fi
        
        if [[ -n "$metadata_json" ]] && ! echo "$metadata_json" | grep -q '"error"'; then
            tmdb_rating=$(echo "$metadata_json" | extract_rating)
            [[ "$tmdb_rating" != "N/A" ]] && movie_rating="$tmdb_rating"
            description=$(echo "$metadata_json" | extract_description)
            [[ -z "$poster_url" || "$poster_url" == "N/A" ]] && poster_url=$(echo "$metadata_json" | python3 -c "import sys, json; data=json.load(sys.stdin); path=data.get('poster_path', ''); print(f'https://image.tmdb.org/t/p/w500{path}' if path else '')" 2>/dev/null)
            # Extract language
            [[ -z "$movie_language" ]] && movie_language=$(echo "$metadata_json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('original_language', ''))" 2>/dev/null)

            if [[ "$is_series" == "true" ]]; then
                tmdb_id=$(echo "$metadata_json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null)
                if [[ -n "$tmdb_id" && "$tmdb_id" != "None" ]]; then
                    full_details=$(get_tv_details "$tmdb_id" 2>/dev/null)
                    
                    # DEBUG LOGGING
                    echo "--- DEBUG $(date) ---" >> /tmp/termflix_debug.log
                    echo "TMDB ID: $tmdb_id" >> /tmp/termflix_debug.log
                    echo "Full Details Length: ${#full_details}" >> /tmp/termflix_debug.log
                    
                    total_seasons=$(echo "$full_details" | python3 -c "import sys, json; print(json.load(sys.stdin).get('number_of_seasons', ''))" 2>/dev/null)
                    echo "Total Seasons: $total_seasons" >> /tmp/termflix_debug.log
                    
                    # Extract genres from TMDB for TV shows
                    if [[ -z "$movie_genre" || "$movie_genre" == "N/A" || "$movie_genre" == "Shows" ]]; then
                        tmdb_genres=$(echo "$full_details" | python3 -c "import sys, json; data=json.load(sys.stdin); print(', '.join([g.get('name', '') for g in data.get('genres', [])]))" 2>/dev/null)
                        [[ -n "$tmdb_genres" && "$tmdb_genres" != "null" ]] && movie_genre="$tmdb_genres"
                    fi
                    
                    # Use persistent season if available, else latest
                    if [[ -n "$selected_preview_season" ]] && [ "$selected_preview_season" -le "${total_seasons:-1}" ]; then
                        latest_season_num="$selected_preview_season"
                        echo "Using selected season: $latest_season_num" >> /tmp/termflix_debug.log
                    else
                        latest_season_num=$(echo "$full_details" | python3 -c "import sys, json; data=json.load(sys.stdin); seasons=[s for s in data.get('seasons', []) if s.get('season_number', 0) > 0]; print(seasons[-1]['season_number'] if seasons else '')" 2>/dev/null)
                        echo "$latest_season_num" > "$season_file"
                        if [[ -n "$imdb_id" ]]; then
                            echo "$latest_season_num" > "$season_file_legacy"
                        fi
                        echo "Calculated latest season: $latest_season_num" >> /tmp/termflix_debug.log
                    fi
                    
                    if [[ -n "$latest_season_num" ]]; then
                        season_details=$(get_tv_season_details "$tmdb_id" "$latest_season_num" 2>/dev/null)
                        echo "Season Details Length: ${#season_details}" >> /tmp/termflix_debug.log
                        # Enhanced episode format with air date and potential watch status
                        # Force UTF-8 encoding for python to handle emojis safely
                        export PYTHONIOENCODING=utf-8
                        episodes_list_raw=$(FZF_COLS="${preview_cols}" python3 -c "
import sys, json, os
from datetime import datetime

# ANSI color codes matching theme
ORANGE = '\033[38;5;208m'
WHITE = '\033[97m'  
CYAN = '\033[36m'
GREEN = '\033[32m'
GRAY = '\033[90m'
RESET = '\033[0m'

# Dynamic title width calculation
# Fixed overhead: status/space/ep/separators + date column
try:
    # Prefer the actual preview width from fzf, fall back to passed hint
    val = os.environ.get('FZF_PREVIEW_COLUMNS') or os.environ.get('FZF_COLS')
    if val:
        available_width = int(float(val))
    else:
        available_width = 80
except Exception:
    available_width = 80

# Treat FZF_PREVIEW_COLUMNS as the usable preview width (fzf already accounts for split/borders).
content_width = max(available_width, 20)

# Table sizing based on preview content width
date_width = 11  # DD MMM YYYY
# Overhead uses display-width columns, not Python string length:
# lock column is 2 cols in most terminals for '🔒', and we always reserve it (two spaces when unlocked).
# Total overhead: lock(2) + spaces(5) + ep(3) + pipes(2) + date(11) = 23
FIXED_OVERHEAD = 23
max_title_col = content_width - FIXED_OVERHEAD
if max_title_col < 10:
    max_title_col = 10

try:
    # Read entire stdin first to debug length if needed
    raw_input = sys.stdin.read()
    if not raw_input:
        with open('/tmp/termflix_debug.log', 'a') as f:
            f.write('PYTHON WARN: Empty stdin input\n')
        data = {}
    else:
        data = json.loads(raw_input)
except Exception as e:
    with open('/tmp/termflix_debug.log', 'a') as f:
        f.write(f'PYTHON JSON ERROR: {str(e)}\n')
        # Write first 100 chars of input to check validity
        if 'raw_input' in locals():
            f.write(f'Input Start: {raw_input[:100]}\n')
    data = {}

today = datetime.now()

eps = data.get('episodes', [])
title_col_width = max_title_col
clip_threshold = title_col_width - 3
if clip_threshold < 1:
    clip_threshold = 1
with open('/tmp/termflix_debug.log', 'a') as f:
    f.write(f'Episodes found: {len(eps)}\n')
    if len(eps) > 0:
        f.write(f'First ep sample: {str(eps[0])[:100]}...\n')

for e in eps:
    try:
        ep_num = e.get('episode_number', 0)
        name = e.get('name', 'TBA')
        air_date_str = e.get('air_date', '')
        
        # Format air date
        if air_date_str:
            try:
                air_date = datetime.strptime(air_date_str, '%Y-%m-%d')
                date_display = air_date.strftime('%d %b %Y')
                if air_date > today:
                    status = '🔒'
                    date_color = GRAY
                else:
                    status = '  '
                    date_color = GREEN
            except Exception:
                date_display = air_date_str[:date_width].ljust(date_width)
                status = '  '
                date_color = CYAN
        else:
            date_display = 'TBA'.ljust(date_width)
            status = '🔒'
            date_color = GRAY
        
        # NOTE: Title truncation intentionally disabled (2025-12-28).
        # We rely on the terminal/fzf preview to handle overflow/wrap.
        
        ep_display = f'E{ep_num:02d}'
        
        # Build line with proper columns
        print(f'{status} {ORANGE}{ep_display}{RESET} │ {WHITE}{name:<{title_col_width}}{RESET} │ {date_color}{date_display:<{date_width}}{RESET}')
    except Exception as e:
        with open('/tmp/termflix_debug.log', 'a') as f:
            f.write(f'Episode parse error: {e}\n')
" <<< "$season_details" 2>&1)
                        py_rc=$?
                        {
                            echo "Python exit: $py_rc"
                            echo "Episodes output length: ${#episodes_list_raw}"
                            echo "Episodes output head: ${episodes_list_raw:0:200}"
                        } >> /tmp/termflix_debug.log
                        if [[ $py_rc -ne 0 || -z "$episodes_list_raw" ]] && command -v jq &>/dev/null; then
                            # Fallback: build episode list via jq if python output is empty
                            preview_cols="${preview_cols:-60}"
                            [[ "$preview_cols" =~ ^[0-9]+$ ]] || preview_cols=60
                            content_width=$((preview_cols))
                            [[ $content_width -lt 20 ]] && content_width=20
                            date_width=11
                            date_fmt="+%d %b %Y"
                            fixed_overhead=23 # lock(2)+spaces(5)+ep(3)+pipes(2)+date(11)
                            title_col_width=$((content_width - fixed_overhead))
                            [[ $title_col_width -lt 10 ]] && title_col_width=10
                            clip_threshold=$((title_col_width - 3))
                            [[ $clip_threshold -lt 1 ]] && clip_threshold=1

                            today_epoch=$(date +%s)
                            episodes_list_raw=""
                            while read -r ep_json; do
                                ep_num=$(echo "$ep_json" | jq -r '.episode_number // 0')
                                ep_name=$(echo "$ep_json" | jq -r '.name // "TBA"')
                                ep_date=$(echo "$ep_json" | jq -r '.air_date // ""')

                                lock_icon="  "
                                formatted_date=$(printf "%-${date_width}s" "TBA")
                                date_color="$GRAY"
                                if [[ -n "$ep_date" && "$ep_date" != "null" ]]; then
                                    ep_epoch=$(date -j -f "%Y-%m-%d" "$ep_date" +%s 2>/dev/null || date -d "$ep_date" +%s 2>/dev/null || echo "0")
                                    date_display=$(date -j -f "%Y-%m-%d" "$ep_date" "$date_fmt" 2>/dev/null || date -d "$ep_date" "$date_fmt" 2>/dev/null || echo "$ep_date")
                                    if [[ "$ep_epoch" -gt "$today_epoch" ]]; then
                                        lock_icon="🔒"
                                        date_color="$GRAY"
                                    else
                                        date_color="$GREEN"
                                    fi
                                    formatted_date=$(printf "%-${date_width}s" "$date_display")
                                else
                                    lock_icon="🔒"
                                    date_color="$GRAY"
                                fi

                                # NOTE: Title truncation intentionally disabled (2025-12-28).
                                # We rely on the terminal/fzf preview to handle overflow/wrap.

                                ep_display=$(printf "E%02d" "$ep_num")
                                episodes_list_raw+="${lock_icon} ${ORANGE}${ep_display}${RESET} │ ${WHITE}$(printf "%-${title_col_width}s" "$ep_name")${RESET} │ ${date_color}${formatted_date}${RESET}"$'\n'
                            done <<< "$(echo "$season_details" | jq -c '.episodes[]' 2>/dev/null)"
                        fi
                    fi
                fi
            else
                # For movies: Extract genres from TMDB (handle both genre_ids and genres)
                if [[ -z "$movie_genre" || "$movie_genre" == "N/A" || "$movie_genre" == "Movies" || "$movie_genre" == "Unknown" ]]; then
                    tmdb_genres=$(echo "$metadata_json" | python3 -c "
import sys, json
# TMDB genre ID to name mapping
GENRE_MAP = {
    28: 'Action', 12: 'Adventure', 16: 'Animation', 35: 'Comedy', 80: 'Crime',
    99: 'Documentary', 18: 'Drama', 10751: 'Family', 14: 'Fantasy', 36: 'History',
    27: 'Horror', 10402: 'Music', 9648: 'Mystery', 10749: 'Romance', 878: 'Sci-Fi',
    10770: 'TV Movie', 53: 'Thriller', 10752: 'War', 37: 'Western'
}
try:
    data = json.load(sys.stdin)
    # Method 1: genres array (from movie details endpoint)
    if data.get('genres'):
        genres = [g.get('name', '') for g in data.get('genres', [])]
        print(', '.join(filter(None, genres)))
    # Method 2: genre_ids array (from search endpoint)
    elif data.get('genre_ids'):
        genres = [GENRE_MAP.get(gid, '') for gid in data.get('genre_ids', [])]
        print(', '.join(filter(None, genres)))
    else:
        print('')
except:
    print('')
" 2>/dev/null)
                    [[ -n "$tmdb_genres" && "$tmdb_genres" != "null" && "$tmdb_genres" != "" ]] && movie_genre="$tmdb_genres"
                fi
            fi
        fi
    fi
fi

# Fallback for description
if [[ -z "$description" || "$description" == "No description available." ]]; then
    if [[ -f "$OMDB_MODULE" ]]; then
        source "$OMDB_MODULE"
        if omdb_configured; then
            description=$(fetch_omdb_description "$clean_title_for_api" "$movie_year" 2>/dev/null)
        fi
    fi
fi

# --- 6. UI: Header & Metadata Bar ---
header_btn=""
[[ "$is_series" == "true" && -n "$latest_season_num" ]] && header_btn="  ${BOLD}${BLUE}[Season ${latest_season_num} ▾]${RESET}"

# Top Title Header with Box Elements
content_emoji="🎬"
[[ "$is_series" == "true" ]] && content_emoji="📺"

# Language flag display
# Fallback: If Language is missing, try OMDB extraction
if [[ -z "$movie_language" && -f "$OMDB_MODULE" ]]; then
    if [[ -z "$omdb_json" ]]; then
        source "$OMDB_MODULE" 2>/dev/null
        if omdb_configured; then
            omdb_json=$(get_omdb_metadata "$clean_title_for_api" "$movie_year" 2>/dev/null)
        fi
    fi
    
    if [[ -n "$omdb_json" ]]; then
        # Extract first language (e.g., "English, Spanish" -> "English")
        omdb_lang=$(echo "$omdb_json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('Language', '').split(',')[0].strip())" 2>/dev/null)
        
        if [[ -n "$omdb_lang" && "$omdb_lang" != "N/A" ]]; then
            # Map full name to ISO code using languages.json
            if [[ -f "${UI_DIR}/../core/languages.sh" ]]; then
                # Ensure languages module is loaded for file path
                source "${UI_DIR}/../core/languages.sh"
            fi
            
            # Helper python script to reverse lookup name -> code
            movie_language=$(python3 -c "
import json, sys
try:
    with open('$LANGUAGES_DATA_FILE') as f:
        data = json.load(f)
    target = '$omdb_lang'.lower()
    for code, info in data.items():
        if info.get('name', '').lower() == target:
            print(code)
            sys.exit(0)
    print('')
except:
    print('')
" 2>/dev/null)
        fi
    fi
fi

language_flag=""
if [[ -n "$movie_language" && "$movie_language" != "" ]]; then
    language_flag=$(get_language_flag "$movie_language" 2>/dev/null)
    [[ -n "$language_flag" ]] && language_flag="${language_flag} "
fi
echo -e "${content_emoji}  ${language_flag}${BOLD}${PURPLE}${display_title}${RESET}${header_btn}"
echo -e "${THEME_DIM:-$GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# --- Sources and IMDB Line (for COMBINED entries) ---
if [[ "$source" == "COMBINED" ]]; then
    IFS='^' read -ra sources_arr <<< "$sources"
    IFS='^' read -ra qualities_arr <<< "$qualities"
    IFS='^' read -ra seeds_arr <<< "$seeds"
    IFS='^' read -ra sizes_arr <<< "$sizes"
    
    # Deduplicate sources
    unique_sources=($(printf "%s\n" "${sources_arr[@]}" | sort -u))
    source_badges=""
    for src in "${unique_sources[@]}"; do
        source_badges+="[${src}]"
    done
    
    # Fetch OMDB metadata for Runtime and Rating (BEFORE printing so movie_rating is set)
    movie_runtime=""
    if [[ -f "$OMDB_MODULE" && "$is_series" == "false" ]]; then
        source "$OMDB_MODULE" 2>/dev/null
        if omdb_configured; then
            omdb_json=$(get_omdb_metadata "$clean_title_for_api" "$movie_year" 2>/dev/null)
            if [[ -n "$omdb_json" ]] && echo "$omdb_json" | grep -q '"Response":"True"'; then
                if [[ -z "$movie_genre" || "$movie_genre" == "N/A" || "$movie_genre" == "Movies" || "$movie_genre" == "Shows" || "$movie_genre" == "Unknown" ]]; then
                    movie_genre=$(echo "$omdb_json" | extract_omdb_genre 2>/dev/null)
                fi
                movie_runtime=$(echo "$omdb_json" | extract_omdb_runtime 2>/dev/null)
                # Extract IMDB rating
                omdb_rating=$(echo "$omdb_json" | extract_omdb_rating 2>/dev/null)
                [[ -n "$omdb_rating" && "$omdb_rating" != "N/A" ]] && movie_rating="$omdb_rating"
            fi
        fi
    fi
    
    # Show Sources and IMDB rating on same line (now movie_rating is set for movies)
    imdb_display=""
    if [[ -n "$movie_rating" ]] && [[ "$movie_rating" != "N/A" ]]; then
        imdb_display="    ${BOLD}IMDB:${RESET} ${YELLOW}⭐ ${movie_rating}${RESET}"
    fi
    echo -e "${BOLD}Sources:${RESET} ${GREEN}${source_badges}${RESET}${imdb_display}"
    
    # Deduplicate and format qualities
    seen_quals=()
    quals_display=""
    for qual in "${qualities_arr[@]}"; do
        if [[ ! " ${seen_quals[*]} " =~ " ${qual} " ]]; then
            seen_quals+=("$qual")
            [[ -n "$quals_display" ]] && quals_display+=", "
            quals_display+="${qual}"
        fi
    done
    
    # Show Available + Seasons on same line (for shows)
    avail_line="${BOLD}Available:${RESET} ${CYAN}${quals_display}${RESET}"
    if [[ "$is_series" == "true" && -n "$total_seasons" ]]; then
        avail_line+="  │  ${BOLD}Seasons:${RESET} ${CYAN}${total_seasons}${RESET}"
    elif [[ -n "$movie_runtime" && "$movie_runtime" != "N/A" ]]; then
        avail_line+="  │  ${BOLD}Runtime:${RESET} ${CYAN}${movie_runtime}${RESET}"
    fi
    echo -e "$avail_line"
else
    # Regular entry
    echo -e "${BOLD}Source:${RESET} ${GREEN}[${source}]${RESET}"
    echo -e "${BOLD}Quality:${RESET} ${CYAN}${quality}${RESET} │ ${BOLD}Size:${RESET} ${YELLOW}${size}${RESET} │ ${BOLD}Seeds:${RESET} ${GREEN}${seeds}${RESET}"
fi

# (Seasons already shown in Available line above for shows)

# --- Genre Line (separate to prevent truncation) ---
if [[ -n "$movie_genre" && "$movie_genre" != "N/A" ]]; then
    styled_genre=$(style_genres "$movie_genre" 2>/dev/null || echo "$movie_genre")
    # \033[0m resets all attrs, \033[49m clears bg specifically, \033[K clears to end of line
    echo -e "${BOLD}Genre:${RESET} ${styled_genre}\033[0m\033[49m\033[K"
fi
echo

# --- 7. UI: Poster ---
IMAGE_HEIGHT=25; IMAGE_WIDTH=30; poster_path=""
if [[ -z "$poster_url" || "$poster_url" == "N/A" ]]; then
    POSTER_SCRIPT="${ROOT_DIR}/lib/termflix/scripts/get_poster.py"
    if [[ -f "$POSTER_SCRIPT" ]]; then
        # Use display_title which preserves subtitle info
        # The get_poster.py script does its own cleaning internally
        poster_url=$(timeout 5s python3 "$POSTER_SCRIPT" "$display_title" 2>/dev/null)
        
        # If that fails, try with just clean_title + year
        if [[ -z "$poster_url" || "$poster_url" == "N/A" || "$poster_url" == "null" ]]; then
            if [[ -n "$movie_year" ]]; then
                poster_url=$(timeout 5s python3 "$POSTER_SCRIPT" "$clean_title_for_api ($movie_year)" 2>/dev/null)
            else
                poster_url=$(timeout 5s python3 "$POSTER_SCRIPT" "$clean_title_for_api" 2>/dev/null)
            fi
        fi
    fi
else
    [[ "${TERMFLIX_DEBUG:-false}" == "true" ]] && echo "DEBUG: Using existing poster_url: $poster_url" >&2
fi

if [[ -n "$poster_url" && "$poster_url" != "N/A" ]]; then
    cache_dir="${HOME}/.cache/termflix/posters"; mkdir -p "$cache_dir"
    filename_hash=$(echo -n "$poster_url" | python3 -c "import sys, hashlib; print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
    poster_path="${cache_dir}/${filename_hash}.png"
    if [[ ! -f "$poster_path" ]]; then
        temp_file="${cache_dir}/${filename_hash}.tmp"
        curl -sL --max-time 5 "$poster_url" -o "$temp_file" 2>/dev/null
        if [[ -f "$temp_file" && -s "$temp_file" ]]; then
            if command -v sips &>/dev/null; then sips -s format png --resampleWidth 400 "$temp_file" --out "$poster_path" &>/dev/null
            else mv "$temp_file" "$poster_path"; fi
            rm -f "$temp_file" 2>/dev/null
        fi
    fi
fi

if [[ -f "$poster_path" && -s "$poster_path" ]]; then
    if [[ "$TERM" == "xterm-kitty" ]] && command -v kitten &>/dev/null; then
        # Kitty: Fixed poster size for optimal preview layout
        KITTY_WIDTH=37
        KITTY_HEIGHT=27
        
        # Clear previous image with blank, then draw poster
        BLANK_IMG="${ROOT_DIR}/lib/torrent/img/blank.png"
        if [[ -f "$BLANK_IMG" ]]; then
            kitten icat --transfer-mode=file --stdin=no \
                --place=${KITTY_WIDTH}x${KITTY_HEIGHT}@0x6 \
                --scale-up "$BLANK_IMG" 2>/dev/null
        fi
        kitten icat --transfer-mode=file --stdin=no \
            --place=${KITTY_WIDTH}x${KITTY_HEIGHT}@0x6 \
            --scale-up --align=left \
            "$poster_path" 2>/dev/null
        # Add newlines to reserve space after image
        for ((i=0; i<KITTY_HEIGHT; i++)); do echo; done
    else
        # Block mode: viu/chafa writes text-based image
        if command -v viu &>/dev/null; then 
            TERM=xterm-256color viu -w $IMAGE_WIDTH -h $IMAGE_HEIGHT "$poster_path" 2>/dev/null
        elif command -v chafa &>/dev/null; then 
            TERM=xterm-256color chafa --symbols=block --size="${IMAGE_WIDTH}x${IMAGE_HEIGHT}" "$poster_path" 2>/dev/null
        fi
    fi
    echo  # Empty line after image
else
    # No poster - use fallback
    FALLBACK_IMG="${ROOT_DIR}/lib/torrent/img/movie_night.jpg"
    if [[ "$TERM" == "xterm-kitty" ]] && command -v kitten &>/dev/null; then
        if [[ -f "$FALLBACK_IMG" ]]; then
            kitten icat --transfer-mode=file --stdin=no \
                --scale-up --align=left "$FALLBACK_IMG" 2>/dev/null
            for ((i=0; i<IMAGE_HEIGHT; i++)); do echo; done
        else
            echo -e "${GRAY}[ No Poster Available ]${RESET}"; echo
        fi
    else
        # Generate rainbow ASCII art poster for text mode (inspired by chafa output)
        # Using block/shade characters with rainbow colors
        local rainbow_colors=(
            "\033[38;5;196m"  # Red
            "\033[38;5;202m"  # Orange
            "\033[38;5;208m"  # Orange-Yellow
            "\033[38;5;214m"  # Yellow
            "\033[38;5;220m"  # Yellow-Green
            "\033[38;5;226m"  # Yellow
            "\033[38;5;46m"   # Green
            "\033[38;5;48m"   # Cyan-Green
            "\033[38;5;51m"   # Cyan
            "\033[38;5;45m"   # Light Blue
            "\033[38;5;39m"   # Blue
            "\033[38;5;33m"   # Dark Blue
            "\033[38;5;129m"  # Purple
            "\033[38;5;165m"  # Magenta
            "\033[38;5;201m"  # Pink
        )
        local chars=("░" "▒" "▓" "█" "▓" "▒" "░" "▒" "▓" "█" "▀" "▄" "▐" "▌" "▆" "▇")
        local num_colors=${#rainbow_colors[@]}
        local num_chars=${#chars[@]}
        local poster_width=24
        local poster_height=18
        
        # Top border
        echo -e "\033[38;5;240m╭$(printf '─%.0s' $(seq 1 $poster_width))╮\033[0m"
        
        for ((row=0; row<poster_height; row++)); do
            local line="\033[38;5;240m│\033[0m"
            for ((col=0; col<poster_width; col++)); do
                local color_idx=$(( (row + col) % num_colors ))
                local char_idx=$(( (row * col + row + col) % num_chars ))
                line+="${rainbow_colors[$color_idx]}${chars[$char_idx]}"
            done
            line+="\033[0m\033[38;5;240m│\033[0m"
            echo -e "$line"
        done
        
        # Bottom border with film reel
        echo -e "\033[38;5;240m╰$(printf '─%.0s' $(seq 1 $poster_width))╯\033[0m"
        echo -e "\033[38;5;245m       🎬 NO POSTER\033[0m"
        echo
    fi
fi

# Print Description (Safe wrapping)
[[ -z "$description" || "$description" == "null" || "$description" == "N/A" ]] && description="No description available."
# Use FZF preview width dynamically, subtract 2 for padding, default to 90 if not available
desc_width=$(( ${preview_cols:-92} - 2 ))
wrapped_desc=$(echo -e "$description" | fold -s -w "$desc_width")
while IFS= read -r line; do
    echo -e "${GRAY}${line}${RESET}"
done <<< "$wrapped_desc"
echo

	# --- 8. UI: Dashboard (Episodes OR Sources) ---
	if [[ "$is_series" == "true" ]]; then
	    if [[ -n "$episodes_list_raw" ]]; then
	        width_note=""
	        if [[ "${TERMFLIX_DEBUG_WIDTH:-}" == "true" || "${TORRENT_DEBUG:-}" == "true" ]]; then
	            w="${FZF_PREVIEW_COLUMNS:-$preview_cols}"
	            if [[ "$w" =~ ^[0-9]+$ ]]; then
	                title_w=$((w - 23))
	                [[ $title_w -lt 10 ]] && title_w=10
	                width_note=" (W=${w} title=${title_w} overhead=23)"
	            else
	                width_note=" (W=${w})"
	            fi
	        fi
	        echo -e "${BOLD}${MAGENTA}󱜙 Season ${latest_season_num} Episodes${width_note}:${RESET}"
	        echo -e "${THEME_DIM:-$GRAY}────────────────────────────────────────────────────────────${RESET}"
	        # Display each episode - colors are embedded in Python output
	        while IFS= read -r ep_line; do
	            echo -e "$ep_line"
	        done <<< "$episodes_list_raw" | head -n 12
    else
        echo -e "${GRAY}No episode data found for this series.${RESET}"
    fi
else
    # Show Sources/Versions (Detailed list for Combined entries)
    if [[ "$source" == "COMBINED" ]]; then
        echo -e "${BOLD}${CYAN}Available Versions:${RESET}"
        echo -e "${THEME_DIM:-$GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo
        
        IFS='^' read -ra s_arr <<< "$sources"
        IFS='^' read -ra q_arr <<< "$qualities"
        IFS='^' read -ra se_arr <<< "$seeds"
        IFS='^' read -ra si_arr <<< "$sizes"
        
        for i in "${!s_arr[@]}"; do
            [[ $i -gt 12 ]] && break
            item_src="${s_arr[$i]}"
            item_qual="${q_arr[$i]}"
            item_seed="${se_arr[$i]}"
            item_size="${si_arr[$i]}"
            
            # Source color
            src_color="$CYAN"
            case "$item_src" in
                "YTS")   src_color="$GREEN" ;;
                "TPB")   src_color="$YELLOW" ;;
                "EZTV")  src_color="$BLUE" ;;
                "1337x") src_color="$MAGENTA" ;;
            esac
            
            # Seed color based on count (green=high, yellow=medium, red=low)
            seed_color="$GREEN"
            seed_num="${item_seed//[^0-9]/}"  # Extract numeric part
            if [[ -n "$seed_num" ]]; then
                if [[ "$seed_num" -ge 100 ]]; then
                    seed_color="$GREEN"
                elif [[ "$seed_num" -ge 10 ]]; then
                    seed_color="$YELLOW"
                else
                    seed_color="${THEME_ERROR:-$C_ERROR}"  # Red for low seeds
                fi
            fi
            
            # Format line without domain, with color-coded seeds
            printf "  ${ORANGE}🧲${RESET} ${src_color}[%s]${RESET} %-8s  -  %-10s  -  ${seed_color}👥 %s seeds${RESET}\n" "$item_src" "$item_qual" "$item_size" "$item_seed"
        done
    else
        echo -e "${BOLD}Source:${RESET} ${GREEN}[${source}]${RESET} │ ${BOLD}Quality:${RESET} ${CYAN}${quality}${RESET}"
        echo -e "${BOLD}Size:${RESET} ${YELLOW}${size}${RESET} │ ${BOLD}Seeds:${RESET} ${GREEN}${seeds} seeds${RESET}"
    fi
fi
echo
