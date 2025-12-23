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

if [[ -z "$TERMFLIX_SCRIPTS_DIR" ]]; then
    TERMFLIX_SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../../scripts" 2>/dev/null && pwd)"
fi

# --- 2. Source Theme & Colors ---
if [[ -f "${SCRIPT_DIR}/../core/theme.sh" ]]; then
    source "${SCRIPT_DIR}/../core/theme.sh"
fi
source "${SCRIPT_DIR}/../core/colors.sh"
[[ -f "${SCRIPT_DIR}/../core/genres.sh" ]] && source "${SCRIPT_DIR}/../core/genres.sh"

# Alias semantic colors (with theme fallback)
MAGENTA="${THEME_GLOW:-$C_GLOW}"
GREEN="${THEME_SUCCESS:-$C_SUCCESS}"
CYAN="${THEME_INFO:-$C_INFO}"
YELLOW="${THEME_WARNING:-$C_WARNING}"
BLUE="${THEME_INFO:-$C_INFO}"
GRAY="${THEME_FG_MUTED:-$C_MUTED}"
ORANGE="${THEME_ORANGE:-$C_ORANGE}"
PURPLE="${THEME_PURPLE:-$C_PURPLE}"

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
clean_title_for_api=$(echo "$title" | sed -E 's/\[SERIES\]//gi; s/\((19|20)[0-9]{2}\)//g; s/[[:space:]]+(19|20)[0-9]{2}//g; s/[[:space:]]+$//; s/^[[:space:]]+//')

# Sanitize display title
display_title="$title"
display_title="${display_title% [SERIES]}"

# Define API Modules
TMDB_MODULE="${SCRIPT_DIR}/../api/tmdb.sh"
OMDB_MODULE="${SCRIPT_DIR}/../api/omdb.sh"

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

# Season Persistence in Preview (Stage 1)
# Title-based hash to remember season selection per show
title_slug=$(echo -n "$clean_title_for_api" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' | head -c 16)
season_file="/tmp/tf_s_${title_slug}"
selected_preview_season=$(cat "$season_file" 2>/dev/null || echo "")

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

            if [[ "$is_series" == "true" ]]; then
                tmdb_id=$(echo "$metadata_json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null)
                if [[ -n "$tmdb_id" && "$tmdb_id" != "None" ]]; then
                    full_details=$(get_tv_details "$tmdb_id" 2>/dev/null)
                    total_seasons=$(echo "$full_details" | python3 -c "import sys, json; print(json.load(sys.stdin).get('number_of_seasons', ''))" 2>/dev/null)
                    
                    # Extract genres from TMDB for TV shows
                    if [[ -z "$movie_genre" || "$movie_genre" == "N/A" || "$movie_genre" == "Shows" ]]; then
                        tmdb_genres=$(echo "$full_details" | python3 -c "import sys, json; data=json.load(sys.stdin); print(', '.join([g.get('name', '') for g in data.get('genres', [])]))" 2>/dev/null)
                        [[ -n "$tmdb_genres" && "$tmdb_genres" != "null" ]] && movie_genre="$tmdb_genres"
                    fi
                    
                    # Use persistent season if available, else latest
                    if [[ -n "$selected_preview_season" ]] && [ "$selected_preview_season" -le "${total_seasons:-1}" ]; then
                        latest_season_num="$selected_preview_season"
                    else
                        latest_season_num=$(echo "$full_details" | python3 -c "import sys, json; data=json.load(sys.stdin); seasons=[s for s in data.get('seasons', []) if s.get('season_number', 0) > 0]; print(seasons[-1]['season_number'] if seasons else '')" 2>/dev/null)
                        echo "$latest_season_num" > "$season_file"
                    fi
                    
                    if [[ -n "$latest_season_num" ]]; then
                        season_details=$(get_tv_season_details "$tmdb_id" "$latest_season_num" 2>/dev/null)
                        # Enhanced episode format with air date and potential watch status
                        episodes_list_raw=$(echo "$season_details" | python3 -c "
import sys, json
from datetime import datetime

# ANSI color codes matching theme
ORANGE = '\033[38;5;208m'  # Episode numbers
WHITE = '\033[97m'
CYAN = '\033[36m'
GREEN = '\033[32m'
GRAY = '\033[90m'
RESET = '\033[0m'

data = json.load(sys.stdin)
today = datetime.now()
lines = []

for e in data.get('episodes', []):
    ep_num = e.get('episode_number', 0)
    name = e.get('name', 'TBA')
    air_date_str = e.get('air_date', '')
    
    # Format air date
    if air_date_str:
        try:
            air_date = datetime.strptime(air_date_str, '%Y-%m-%d')
            date_display = air_date.strftime('%d %b %Y')
            # Check if episode has aired
            if air_date > today:
                status = '🔒'  # Upcoming
                date_color = GRAY
            else:
                status = '  '  # Aired (can be watched)
                date_color = GREEN
        except:
            date_display = air_date_str
            status = '  '
            date_color = CYAN
    else:
        date_display = 'TBA'
        status = '🔒'
        date_color = GRAY
    
    # Colorful format: magenta episode num, white name, colored date
    lines.append(f'{status} {ORANGE}E{ep_num:02d}{RESET} │ {WHITE}{name[:25]:<25}{RESET} │ {date_color}{date_display}{RESET}')

print('\\n'.join(lines))
" 2>/dev/null)
                    fi
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
echo -e "${content_emoji}  ${BOLD}${PURPLE}${display_title}${RESET}${header_btn}"
echo -e "${THEME_DIM:-$GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

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
    
    # Show Sources and IMDB rating on same line
    imdb_display=""
    if [[ -n "$movie_rating" ]] && [[ "$movie_rating" != "N/A" ]]; then
        imdb_display="    ${BOLD}IMDB:${RESET} ${YELLOW}⭐ ${movie_rating}${RESET}"
    fi
    echo -e "${BOLD}Sources:${RESET} ${GREEN}${source_badges}${RESET}${imdb_display}"
    
    # Fetch OMDB metadata for Runtime and Rating
    movie_runtime=""
    if [[ -f "$OMDB_MODULE" && "$is_series" == "false" ]]; then
        source "$OMDB_MODULE" 2>/dev/null
        if omdb_configured; then
            omdb_json=$(get_omdb_metadata "$clean_title_for_api" "$movie_year" 2>/dev/null)
            if [[ -n "$omdb_json" ]] && echo "$omdb_json" | grep -q '"Response":"True"'; then
                [[ -z "$movie_genre" || "$movie_genre" == "N/A" ]] && movie_genre=$(echo "$omdb_json" | extract_omdb_genre 2>/dev/null)
                movie_runtime=$(echo "$omdb_json" | extract_omdb_runtime 2>/dev/null)
                # Extract IMDB rating
                omdb_rating=$(echo "$omdb_json" | extract_omdb_rating 2>/dev/null)
                [[ -n "$omdb_rating" && "$omdb_rating" != "N/A" ]] && movie_rating="$omdb_rating"
            fi
        fi
    fi
    
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
    echo -e "${BOLD}Genre:${RESET} ${styled_genre}"
fi
echo

# --- 7. UI: Poster ---
IMAGE_HEIGHT=30; IMAGE_WIDTH=40; poster_path=""
if [[ -z "$poster_url" || "$poster_url" == "N/A" ]]; then
    POSTER_SCRIPT="$(cd \"$SCRIPT_DIR/../../..\" 2>/dev/null && pwd)/lib/termflix/scripts/get_poster.py"
    if [[ -f "$POSTER_SCRIPT" ]]; then
        poster_url=$(timeout 3s python3 "$POSTER_SCRIPT" "$clean_title_for_api ($movie_year)" 2>/dev/null)
    fi
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
        # Kitty: Scale poster based on available space
        # Use FZF_PREVIEW_COLUMNS/LINES if available, else defaults
        KITTY_WIDTH=${FZF_PREVIEW_COLUMNS:-40}
        KITTY_HEIGHT=${FZF_PREVIEW_LINES:-30}
        # Limit to reasonable max
        ((KITTY_WIDTH = KITTY_WIDTH > 45 ? 45 : KITTY_WIDTH))
        ((KITTY_HEIGHT = KITTY_HEIGHT > 30 ? 30 : KITTY_HEIGHT))
        
        # Clear previous image with blank, then draw poster
        BLANK_IMG="${SCRIPT_DIR%/bin/modules/ui}/lib/torrent/img/blank.png"
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
    FALLBACK_IMG="${SCRIPT_DIR%/bin/modules/ui}/lib/torrent/img/movie_night.jpg"
    if [[ "$TERM" == "xterm-kitty" ]] && command -v kitten &>/dev/null; then
        if [[ -f "$FALLBACK_IMG" ]]; then
            kitten icat --transfer-mode=file --stdin=no \
                --scale-up --align=left "$FALLBACK_IMG" 2>/dev/null
            for ((i=0; i<IMAGE_HEIGHT; i++)); do echo; done
        else
            echo -e "${GRAY}[ No Poster Available ]${RESET}"; echo
        fi
    else
        echo -e "${GRAY}[ No Poster Available ]${RESET}"; echo
    fi
fi

# Print Description (Safe wrapping)
[[ -z "$description" || "$description" == "null" || "$description" == "N/A" ]] && description="No description available."
wrapped_desc=$(echo -e "$description" | fmt -w 60)
while IFS= read -r line; do
    echo -e "${GRAY}${line}${RESET}"
done <<< "$wrapped_desc"
echo

# --- 8. UI: Dashboard (Episodes OR Sources) ---
if [[ "$is_series" == "true" ]]; then
    if [[ -n "$episodes_list_raw" ]]; then
        echo -e "${BOLD}${MAGENTA}󱜙 Season ${latest_season_num} Episodes:${RESET}"
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
