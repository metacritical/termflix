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

# Alias semantic colors (with theme fallback)
MAGENTA="${THEME_GLOW:-$C_GLOW}"
GREEN="${THEME_SUCCESS:-$C_SUCCESS}"
CYAN="${THEME_INFO:-$C_INFO}"
YELLOW="${THEME_WARNING:-$C_WARNING}"
BLUE="${THEME_INFO:-$C_INFO}"
GRAY="${THEME_FG_MUTED:-$C_MUTED}"
ORANGE="${THEME_ORANGE:-$C_ORANGE}"
PURPLE="${THEME_PURPLE:-$C_PURPLE}"

# --- 3. Parse Entry ---
IFS='|' read -r source title rest <<< "$input_line"

# Display title header
echo -e "${BOLD}${MAGENTA}${title}${RESET}"
echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

# --- 4. Handle COMBINED vs Regular Entries ---
if [[ "$source" == "COMBINED" ]]; then
    # Parse NEW COMBINED format: Sources|Qualities|Seeds|Sizes|Magnets|Poster|IMDBRating|Plot
    IFS='|' read -r sources qualities seeds sizes magnets poster_url imdb_rating plot_text <<< "$rest"
    
    # Split into arrays
    IFS='^' read -ra sources_arr <<< "$sources"
    IFS='^' read -ra qualities_arr <<< "$qualities"
    IFS='^' read -ra seeds_arr <<< "$seeds"
    IFS='^' read -ra sizes_arr <<< "$sizes"
    IFS='^' read -ra magnets_arr <<< "$magnets"
    
    # Deduplicate sources
    unique_sources=($(printf "%s\n" "${sources_arr[@]}" | sort -u))
    
    # Display unique sources with IMDB rating
    source_badges=""
    for src in "${unique_sources[@]}"; do
        source_badges+="[${src}]"
    done
    
    # Show Sources and IMDB rating on same line
    imdb_display=""
    if [[ -n "$imdb_rating" ]] && [[ "$imdb_rating" != "N/A" ]]; then
        imdb_display="    ${BOLD}IMDB:${RESET} ${YELLOW}⭐ ${imdb_rating}${RESET}"
    fi
    echo -e "${BOLD}Sources:${RESET} ${GREEN}${source_badges}${RESET}${imdb_display}"
    
    # Deduplicate and format qualities only (no sizes)
    seen_quals=()
    quals_display=""
    for i in "${!qualities_arr[@]}"; do
        qual="${qualities_arr[$i]}"
        
        # Check if we've seen this quality before
        if [[ ! " ${seen_quals[@]} " =~ " ${qual} " ]]; then
            seen_quals+=("$qual")
            [[ -n "$quals_display" ]] && quals_display+=", "
            quals_display+="${qual}"
        fi
    done
    
    echo -e "${BOLD}Available:${RESET} ${CYAN}${quals_display}${RESET}"
    
    # Store plot for later display (don't fetch if already provided)
    if [[ -n "$plot_text" ]] && [[ "$plot_text" != "N/A" ]]; then
        description="$plot_text"
    fi
    
else
    # Regular entry: Source|Title|Magnet|Quality|Size|Seeds|Poster
    IFS='|' read -r magnet quality size seeds poster_url <<< "$rest"
    
    echo -e "${BOLD}Source:${RESET} ${GREEN}[${source}]${RESET}"
    echo -e "${BOLD}Quality:${RESET} ${CYAN}${quality}${RESET} │ ${BOLD}Size:${RESET} ${YELLOW}${size}${RESET} │ ${BOLD}Seeds:${RESET} ${GREEN}${seeds}${RESET}"
fi

# --- 4.5 Fetch Rich Metadata (Genre, Runtime, Rating, Year) ---
OMDB_MODULE="${SCRIPT_DIR}/../api/omdb.sh"

# Variables for rich metadata
movie_genre=""
movie_runtime=""
movie_rating=""
movie_year_api=""

# Clean title for API lookup
clean_title_for_api="$title"
movie_year=""

# Extract year from title
if [[ "$title" =~ (19[0-9]{2}|20[0-9]{2}) ]]; then
    movie_year="${BASH_REMATCH[1]}"
fi

# Remove quality tags from title for API lookup
clean_title_for_api=$(echo "$title" | sed -E '
    s/[[:space:]]*(19|20)[0-9]{2}[[:space:]]*/ /g;
    s/[[:space:]]*(1080p|720p|480p|2160p|4K|UHD)//gi;
    s/[[:space:]]*(HDRip|BRRip|BluRay|WEBRip|HDTV|DVDRip|CAM|TS|TC|HDCAM|WEB-DL|WEBDL)//gi;
    s/[[:space:]]*(HEVC|x264|x265|H264|H265|AVC|AAC|DTS|AC3)//gi;
    s/[[:space:]]+(YTS|YIFY|RARBG|EZTV)//gi;
    s/[[:space:]]+/ /g;
    s/^[[:space:]]+//;
    s/[[:space:]]+$//
')

# Fetch metadata from OMDB if module available
if [[ -f "$OMDB_MODULE" ]]; then
    source "$OMDB_MODULE"
    if omdb_configured; then
        # Get full metadata JSON
        metadata_json=$(get_omdb_metadata "$clean_title_for_api" "$movie_year" 2>/dev/null)
        
        if [[ -n "$metadata_json" ]] && echo "$metadata_json" | grep -q '"Response":"True"'; then
            movie_genre=$(echo "$metadata_json" | extract_omdb_genre)
            movie_runtime=$(echo "$metadata_json" | extract_omdb_runtime)
            movie_rating=$(echo "$metadata_json" | extract_omdb_rating)
            movie_year_api=$(echo "$metadata_json" | extract_omdb_year)
            
            # Update year if we got it from API
            [[ -n "$movie_year_api" && "$movie_year_api" != "N/A" ]] && movie_year="$movie_year_api"
        fi
    fi
fi

# Display rich metadata line (Year | Genre | Runtime) - Rating already shown in Sources line
metadata_line=""
if [[ -n "$movie_year" && "$movie_year" != "N/A" ]]; then
    metadata_line+="${BOLD}Year:${RESET} ${CYAN}${movie_year}${RESET}"
fi
if [[ -n "$movie_genre" && "$movie_genre" != "N/A" ]]; then
    [[ -n "$metadata_line" ]] && metadata_line+="  │  "
    metadata_line+="${BOLD}Genre:${RESET} ${PURPLE}${movie_genre}${RESET}"
fi
if [[ -n "$movie_runtime" && "$movie_runtime" != "N/A" ]]; then
    [[ -n "$metadata_line" ]] && metadata_line+="  │  "
    metadata_line+="${BOLD}Runtime:${RESET} ${CYAN}${movie_runtime}${RESET}"
fi

# Only print if we have metadata
if [[ -n "$metadata_line" ]]; then
    echo -e "$metadata_line"
fi

echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

# --- 5. Fetch Movie Description (OMDB → TMDB → Google fallback) ---
OMDB_MODULE="${SCRIPT_DIR}/../api/omdb.sh"
TMDB_MODULE="${SCRIPT_DIR}/../api/tmdb.sh"
GOOGLE_SCRIPT="${SCRIPT_DIR}/../../scripts/google_poster.py"
description=""

# Clean title: remove quality tags, codecs, release info
# Example: "Zootopia 2 2025 1080p TS EN-RGB" -> "Zootopia 2" with year "2025"
movie_year=""
clean_title="$title"

# Extract year (4 digits that look like a year 19xx or 20xx)
if [[ "$title" =~ (19[0-9]{2}|20[0-9]{2}) ]]; then
    movie_year="${BASH_REMATCH[1]}"
fi

# Remove quality and codec tags
clean_title=$(echo "$title" | sed -E '
    s/[[:space:]]*(19|20)[0-9]{2}[[:space:]]*/ /g;
    s/[[:space:]]*(1080p|720p|480p|2160p|4K|UHD)//gi;
    s/[[:space:]]*(HDRip|BRRip|BluRay|WEBRip|HDTV|DVDRip|CAM|TS|TC|HDCAM|WEB-DL|WEBDL)//gi;
    s/[[:space:]]*(HEVC|x264|x265|H264|H265|AVC|AAC|DTS|AC3)//gi;
    s/[[:space:]]*(EN-RGB|BONE|YIFY|SPARKS|RARBG|ETRG)//gi;
    s/[[:space:]]+/ /g;
    s/^[[:space:]]+//;
    s/[[:space:]]+$//
')

# --- Priority 0: Check cached description FIRST (instant) ---
DESC_CACHE="${HOME}/.cache/termflix/descriptions"
title_hash=$(echo -n "$title" | tr '[:upper:]' '[:lower:]' | python3 -c "import sys, hashlib; print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
cached_desc="${DESC_CACHE}/${title_hash}.txt"
if [[ -f "$cached_desc" ]]; then
    description=$(cat "$cached_desc")
fi

# --- Priority 1: OMDB (if not cached) ---
if [[ -z "$description" && -f "$OMDB_MODULE" ]]; then
    source "$OMDB_MODULE"
    if omdb_configured; then
        description=$(fetch_omdb_description "$clean_title" "$movie_year" 2>/dev/null)
        # Cache it for next time
        if [[ -n "$description" && "$description" != "null" ]]; then
            mkdir -p "$DESC_CACHE"
            echo "$description" > "$cached_desc"
        fi
    fi
fi

# --- Priority 2: TMDB (fallback) ---
if [[ -z "$description" && -f "$TMDB_MODULE" ]]; then
    source "$TMDB_MODULE"
    if tmdb_configured; then
        description=$(fetch_movie_description "$clean_title" "$movie_year" 2>/dev/null)
        # Cache it for next time
        if [[ -n "$description" && "$description" != "null" ]]; then
            mkdir -p "$DESC_CACHE"
            echo "$description" > "$cached_desc"
        fi
    fi
fi

# --- Priority 3: Google scraping (last resort) ---
if [[ -z "$description" && -f "$GOOGLE_SCRIPT" ]]; then
    # Google scraping would go here - placeholder for now
    description=""
fi

# Fallback message if no API configured or no results
if [[ -z "$description" || "$description" == "null" || "$description" == "N/A" ]]; then
    description="No description available."
fi

# --- 6. Display Poster + Description Side-by-Side ---
# Fetch poster URL on-demand if not provided
if [[ -z "$poster_url" || "$poster_url" == "N/A" || "$poster_url" == "null" ]]; then
    # Try to fetch poster URL using get_poster.py
    POSTER_SCRIPT="${TERMFLIX_SCRIPTS_DIR}/get_poster.py"
    if [[ -f "$POSTER_SCRIPT" ]] && command -v python3 &>/dev/null; then
        poster_url=$(timeout 3s python3 "$POSTER_SCRIPT" "$clean_title ($movie_year)" 2>/dev/null)
    fi
fi

# Image height for block mode
IMAGE_HEIGHT=15
IMAGE_WIDTH=20

# Download poster if we have URL
poster_path=""
if [[ -n "$poster_url" && "$poster_url" != "N/A" && "$poster_url" != "null" ]]; then
    cache_dir="${HOME}/.cache/termflix/posters"
    mkdir -p "$cache_dir"
    
    filename_hash=$(echo -n "$poster_url" | python3 -c "import sys, hashlib; print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
    poster_path="${cache_dir}/${filename_hash}.png"
    
    # Download and convert to PNG if not cached
    if [[ ! -f "$poster_path" ]]; then
        temp_file="${cache_dir}/${filename_hash}.tmp"
        curl -sL --max-time 5 "$poster_url" -o "$temp_file" 2>/dev/null
        
        # Convert to PNG using sips (macOS)
        if [[ -f "$temp_file" && -s "$temp_file" ]]; then
            if command -v sips &>/dev/null; then
                sips -s format png --resampleWidth 400 "$temp_file" --out "$poster_path" &>/dev/null
            else
                mv "$temp_file" "$poster_path"
            fi
            rm -f "$temp_file" 2>/dev/null
        fi
    fi
fi

# Display image or placeholder
BLANK_IMG="${SCRIPT_DIR%/bin/modules/ui}/lib/torrent/img/blank.png"

if [[ -f "$poster_path" && -s "$poster_path" ]]; then
    if [[ "$TERM" == "xterm-kitty" ]] && command -v kitten &>/dev/null; then
        # Kitty: Draw larger blank first to fully erase previous, then poster at normal size
        if [[ -f "$BLANK_IMG" ]]; then
            kitten icat --transfer-mode=file --stdin=no \
                --place=20x16@0x0 \
                --scale-up "$BLANK_IMG" 2>/dev/null
        fi
        kitten icat --transfer-mode=file --stdin=no \
            --place=${IMAGE_WIDTH}x${IMAGE_HEIGHT}@0x0 \
            --scale-up --align=left \
            "$poster_path" 2>/dev/null
        # Add newlines to reserve space after image
        for ((i=0; i<IMAGE_HEIGHT; i++)); do echo; done
    else
        # Block mode: viu/chafa writes text-based image
        if command -v viu &>/dev/null; then
            TERM=xterm-256color viu -w $IMAGE_WIDTH -h $IMAGE_HEIGHT "$poster_path" 2>/dev/null
        elif command -v chafa &>/dev/null; then
            TERM=xterm-256color chafa --symbols=block --size="${IMAGE_WIDTH}x${IMAGE_HEIGHT}" "$poster_path" 2>/dev/null
        fi
    fi
else
    # No poster available - different fallbacks for Kitty vs text mode
    FALLBACK_IMG="${SCRIPT_DIR%/bin/modules/ui}/lib/torrent/img/movie_night.jpg"
    
    if [[ "$TERM" == "xterm-kitty" ]] && command -v kitten &>/dev/null; then
        # Kitty: Use movie_night.jpg fallback image
        if [[ -f "$FALLBACK_IMG" ]]; then
            kitten icat --transfer-mode=file --stdin=no \
                --place=${IMAGE_WIDTH}x${IMAGE_HEIGHT}@0x0 \
                --scale-up --align=left "$FALLBACK_IMG" 2>/dev/null
            for ((i=0; i<IMAGE_HEIGHT; i++)); do echo; done
        fi
    else
        # Text/block mode: Draw colorful rainbow spinner grid
        _draw_spinner_grid() {
            local w=$1 h=$2
            local spinners=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
            local colors=(196 202 208 214 220 226 190 154 118 82 46 47 48 49 50 51 45 39 33 27 21 57 93 129 165 201 200 199 198 197)
            
            for ((row=0; row<h; row++)); do
                local line=""
                for ((col=0; col<w; col++)); do
                    local spin_idx=$(( (row + col) % ${#spinners[@]} ))
                    local color_idx=$(( (row * w + col) % ${#colors[@]} ))
                    line+="\033[38;5;${colors[$color_idx]}m${spinners[$spin_idx]}"
                done
                echo -e "${line}\033[0m"
            done
        }
        _draw_spinner_grid $IMAGE_WIDTH $IMAGE_HEIGHT
    fi
fi

echo
echo -e "${DIM}${description}${RESET}"
echo

# --- 7. Magnet Picker Menu ---
if [[ "$source" == "COMBINED" ]]; then
    echo -e "${BOLD}${CYAN}Available Versions:${RESET}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
    
    # Deduplicate by magnet hash (bash 3 compatible)
    seen_hashes=""
    unique_indices=()
    
    for i in "${!magnets_arr[@]}"; do
        mag="${magnets_arr[$i]}"
        # Extract hash from magnet link
        hash=$(echo "$mag" | grep -oE 'btih:[a-fA-F0-9]+' | cut -d: -f2 | tr '[:upper:]' '[:lower:]')
        
        # Check if we've seen this hash (simple string grep)
        if [[ -n "$hash" ]] && [[ ! "$seen_hashes" =~ $hash ]]; then
            seen_hashes+="$hash "
            unique_indices+=("$i")
        fi
    done
    
    # Display only unique entries
    for i in "${unique_indices[@]}"; do
        src="${sources_arr[$i]}"
        qual="${qualities_arr[$i]}"
        seed="${seeds_arr[$i]}"
        sz="${sizes_arr[$i]}"
        
        # Source color
        src_color="$CYAN"
        case "$src" in
            "YTS")   src_color="$GREEN" ;;
            "TPB")   src_color="$YELLOW" ;;
            "EZTV")  src_color="$BLUE" ;;
            "1337x") src_color="$MAGENTA" ;;
        esac
        
        # Source name
        src_name=""
        case "$src" in
            "YTS")   src_name="YTS.mx" ;;
            "TPB")   src_name="ThePirateBay" ;;
            "EZTV")  src_name="EZTV.re" ;;
            "1337x") src_name="1337x.to" ;;
        esac
        
        echo -e "  ${ORANGE}🧲${RESET} ${src_color}[${src}]${RESET} ${CYAN}${qual}${RESET} - ${YELLOW}${sz}${RESET} - ${GREEN}👥 ${seed} seeds${RESET} ${DIM}- ${src_name}${RESET}"
    done
else
    echo -e "${BOLD}${GREEN}Ready to stream:${RESET}"
    echo -e "  ${ORANGE}🧲${RESET} ${GREEN}[${source}]${RESET} ${CYAN}${quality}${RESET} - ${YELLOW}${size}${RESET} - ${GREEN}👥 ${seeds} seeds${RESET}"
fi

echo
