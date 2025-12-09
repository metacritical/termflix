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

# --- 2. Styling ---
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
MAGENTA='\033[38;5;213m'
GREEN='\033[38;5;46m'
CYAN='\033[38;5;87m'
YELLOW='\033[38;5;220m'
BLUE='\033[38;5;81m'
GRAY='\033[38;5;241m'
ORANGE='\033[38;5;208m'

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
    
    # Deduplicate and format qualities/sizes  
    seen_quals=()
    sizes_display=""
    for i in "${!qualities_arr[@]}"; do
        qual="${qualities_arr[$i]}"
        sz="${sizes_arr[$i]}"
        
        # Check if we've seen this quality before
        if [[ ! " ${seen_quals[@]} " =~ " ${qual} " ]]; then
            seen_quals+=("$qual")
            [[ -n "$sizes_display" ]] && sizes_display+=", "
            sizes_display+="${qual} (${sz})"
        fi
    done
    
    echo -e "${BOLD}Available:${RESET} ${CYAN}${sizes_display}${RESET}"
    
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

# --- Priority 1: OMDB ---
if [[ -z "$description" && -f "$OMDB_MODULE" ]]; then
    source "$OMDB_MODULE"
    if omdb_configured; then
        description=$(fetch_omdb_description "$clean_title" "$movie_year" 2>/dev/null)
    fi
fi

# --- Priority 2: TMDB (fallback) ---
if [[ -z "$description" && -f "$TMDB_MODULE" ]]; then
    source "$TMDB_MODULE"
    if tmdb_configured; then
        description=$(fetch_movie_description "$clean_title" "$movie_year" 2>/dev/null)
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
# Fetch and display poster
if [[ -n "$poster_url" && "$poster_url" != "N/A" && "$poster_url" != "null" ]]; then
    cache_dir="${HOME}/.cache/termflix/posters"
    mkdir -p "$cache_dir"
    
    filename_hash=$(echo -n "$poster_url" | python3 -c "import sys, hashlib; print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
    poster_path="${cache_dir}/${filename_hash}.jpg"
    
    # Download if not cached
    if [[ ! -f "$poster_path" ]]; then
        curl -sL --max-time 3 "$poster_url" -o "$poster_path" 2>/dev/null
    fi

    # Display Image
    if [[ -f "$poster_path" && -s "$poster_path" ]]; then
        if command -v viu &>/dev/null; then
            viu -w 20 -h 15 "$poster_path" 2>/dev/null
        elif command -v chafa &>/dev/null; then
            chafa --symbols=block --size="20x15" "$poster_path" 2>/dev/null
        fi
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
