#!/usr/bin/env bash
#
# Termflix FZF Preview Script
# Renders details and images for the selected torrent item in the FZF preview window
#

# --- 1. Parse Input ---
# The input line comes from FZF: "{Index}|{Source}|{Title}|{Quality}|{Size}|{PosterURL}|{Details...}"
input_line="$1"

# Extract fields (assuming pipe delimiter)
IFS='|' read -r index source title magnet quality size extra poster_url <<< "$input_line"

# If input is empty (e.g. header), exit
[[ -z "$title" ]] && exit 0

# --- 2. Styling Helpers ---
RESET='\033[0m'
BOLD='\033[1m'
MAGENTA='\033[38;5;213m'
PURPLE='\033[38;5;135m'
GREEN='\033[38;5;46m'
CYAN='\033[38;5;87m'
YELLOW='\033[38;5;220m'
BLUE='\033[38;5;81m'
GRAY='\033[38;5;241m'

# Source Color
src_color="$CYAN"
case "$source" in
    "YTS")   src_color="$GREEN" ;;
    "TPB")   src_color="$YELLOW" ;;
    "EZTV")  src_color="$BLUE" ;;
    "1337x") src_color="$MAGENTA" ;;
esac

# --- 3. Render Text Details ---
echo -e "${BOLD}${MAGENTA}${title}${RESET}"
echo -e "${GRAY}----------------------------------------${RESET}"
echo -e "${BOLD}Source:${RESET}  ${src_color}${source}${RESET}"
echo -e "${BOLD}Quality:${RESET} ${CYAN}${quality:-N/A}${RESET}"
echo -e "${BOLD}Size:${RESET}    ${YELLOW}${size:-N/A}${RESET}"
if [[ "$extra" != "N/A" ]]; then
    echo -e "${BOLD}Seeds:${RESET}   ${GREEN}${extra}${RESET}"
fi
echo -e "${GRAY}----------------------------------------${RESET}"
echo

# --- 4. Lazy Poster Fetching ---
# If URL is missing, try to find it via Google/TMDB
if [[ -z "$poster_url" || "$poster_url" == "N/A" ]]; then
    # Create valid hash using Python (cross-platform)
    filename_hash=$(echo -n "$title" | python3 -c "import sys, hashlib; print(hashlib.md5(sys.stdin.read().encode()).hexdigest())")
    url_cache_dir="${HOME}/.cache/termflix/urls"
    url_cache_file="${url_cache_dir}/${filename_hash}"
    mkdir -p "$url_cache_dir"
    
    if [[ -f "$url_cache_file" ]]; then
        poster_url=$(cat "$url_cache_file")
    else
        # Only attempt fetch if we have the script
        if [[ -f "$TERMFLIX_SCRIPTS_DIR/get_poster.py" ]]; then
             echo -e "${GRAY}Fetching poster metadata...${RESET}"
             # Run with timeout
             fetched_url=$(timeout 3s python3 "$TERMFLIX_SCRIPTS_DIR/get_poster.py" "$title" 2>/dev/null)
             if [[ -n "$fetched_url" && "$fetched_url" != "null" ]]; then
                 poster_url="$fetched_url"
                 echo "$poster_url" > "$url_cache_file"
                 # Clear "Fetching..." line
                 echo -e "\033[1A\033[K" 
             else
                 echo -e "${GRAY}[Poster not found]${RESET}"
                 echo "N/A" > "$url_cache_file"
             fi
        fi
    fi
fi

# --- 5. Render Image ---
# Verify we have a poster URL
if [[ -n "$poster_url" && "$poster_url" != "N/A" && "$poster_url" != "null" ]]; then
    
    # Define cache path
    cache_dir="${HOME}/.cache/termflix/posters"
    mkdir -p "$cache_dir"
    
    # Hash the URL
    filename_hash=$(echo -n "$poster_url" | python3 -c "import sys, hashlib; print(hashlib.md5(sys.stdin.read().encode()).hexdigest())")
    poster_path="${cache_dir}/${filename_hash}.jpg"
    
    # Download if not cached
    if [[ ! -f "$poster_path" ]]; then
        echo -e "${GRAY}Downloading poster...${RESET}"
        curl -sL --max-time 3 "$poster_url" -o "$poster_path"
        # Clear "Downloading..." line
        echo -e "\r\033[K"
    fi

    # Display Image if file exists
    if [[ -f "$poster_path" ]]; then
        
        # Calculate Dimensions
        local width=${FZF_PREVIEW_COLUMNS:-40}
        local height=${FZF_PREVIEW_LINES:-20}
        ((height-=10))
        [[ $height -lt 5 ]] && height=5
        
        # Priority 1: Kitty ICAT (if in Kitty terminal)
        if [[ "$TERM" == "xterm-kitty" ]] && command -v kitten &>/dev/null; then
             # FZF preview requires robust placement.
             # Standard icat works if FZF doesn't overwrite it immediately.
             # Using 'place' is safer for positioning.
             # But 'kitten icat' prints to stdout.
             kitten icat --transfer-mode=memory --stdin=no --place "${width}x${height}@0x0" "$poster_path" < /dev/null
             
        # Priority 2: VIU (User Preferred)
        elif command -v viu &>/dev/null; then
             # Viu needs explicit size or it autodetects.
             # Pass width/height via flags? Viu -w -h
             viu -w "$width" -h "$height" "$poster_path"
             
        # Priority 3: Chafa (Robust Fallback)
        elif command -v chafa &>/dev/null; then
             chafa --symbols=block --size="${width}x${height}" "$poster_path"
             
        else
            echo -e "${GRAY}[Install 'viu', 'kitten', or 'chafa' to see images]${RESET}"
        fi
    else
        echo -e "${GRAY}[Poster Download Failed]${RESET}"
    fi
else
    # Only show this if we really couldn't find one
    if [[ "$poster_url" == "N/A" ]]; then
        echo -e "${GRAY}[No Poster Metadata]${RESET}"
    fi
fi
