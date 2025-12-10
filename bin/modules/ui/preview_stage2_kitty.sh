#!/usr/bin/env bash
#
# Stage 2 Preview Script for KITTY Terminal
# Looks like Stage 1: Title + Sources + Poster + Description + Selected Version Info
# The version picker is on the LEFT (FZF), this preview is on the RIGHT
#

# --- 1. Resolve Script Directory ---
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR_TMP="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR_TMP/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"

if [[ -z "$TERMFLIX_SCRIPTS_DIR" ]]; then
    TERMFLIX_SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../../scripts" 2>/dev/null && pwd)"
fi

# --- 2. Styling ---
RESET=$'\e[0m'
BOLD=$'\e[1m'
DIM=$'\e[2m'
MAGENTA=$'\e[38;5;213m'
GREEN=$'\e[38;5;46m'
CYAN=$'\e[38;5;87m'
YELLOW=$'\e[38;5;220m'
GRAY=$'\e[38;5;241m'
WHITE=$'\e[38;5;255m'

# --- 3. Parse Input ---
# Receives: title|source|quality|size|poster_url
IFS='|' read -r title source quality size poster_url <<< "$1"

# --- 4. Display Title (like Stage 1) ---
echo -e "${BOLD}${MAGENTA}${title}${RESET}"
echo -e "${GRAY}────────────────────────────────────────${RESET}"
echo

# --- 5. Display Sources + Available (like Stage 1) ---
echo -e "${BOLD}Sources:${RESET} ${GREEN}[${source}]${RESET}"
echo -e "${BOLD}Available:${RESET} ${CYAN}${quality}${RESET} ${DIM}(${size})${RESET}"
echo

# --- 6. Image dimensions (same as Stage 1: 20x15) ---
IMAGE_WIDTH=20
IMAGE_HEIGHT=15
BLANK_IMG="${SCRIPT_DIR%/bin/modules/ui}/lib/torrent/img/blank.png"
FALLBACK_IMG="${SCRIPT_DIR%/bin/modules/ui}/lib/torrent/img/movie_night.jpg"

# --- 7. Fetch poster URL if not provided ---
if [[ -z "$poster_url" || "$poster_url" == "N/A" || "$poster_url" == "null" ]]; then
    POSTER_SCRIPT="${SCRIPT_DIR%/bin/modules/ui}/bin/scripts/get_poster.py"
    if [[ -f "$POSTER_SCRIPT" ]] && command -v python3 &>/dev/null && [[ -n "$title" ]]; then
        poster_url=$(timeout 3s python3 "$POSTER_SCRIPT" "$title" 2>/dev/null)
    fi
fi

# --- 8. Download/cache poster ---
poster_path=""
if [[ -n "$poster_url" && "$poster_url" != "N/A" && "$poster_url" != "null" ]]; then
    cache_dir="${HOME}/.cache/termflix/posters"
    mkdir -p "$cache_dir"
    
    filename_hash=$(echo -n "$poster_url" | python3 -c "import sys, hashlib; print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
    poster_path="${cache_dir}/${filename_hash}.png"
    
    if [[ ! -f "$poster_path" ]]; then
        temp_file="${cache_dir}/${filename_hash}.tmp"
        curl -sL --max-time 5 "$poster_url" -o "$temp_file" 2>/dev/null
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

# --- 9. Display Poster using kitten icat ---
if [[ -f "$poster_path" && -s "$poster_path" ]]; then
    # Draw blank first to clear previous, then poster
    if [[ -f "$BLANK_IMG" ]]; then
        kitten icat --transfer-mode=file --stdin=no \
            --place=${IMAGE_WIDTH}x${IMAGE_HEIGHT}@0x0 \
            --scale-up "$BLANK_IMG" 2>/dev/null
    fi
    kitten icat --transfer-mode=file --stdin=no \
        --place=${IMAGE_WIDTH}x${IMAGE_HEIGHT}@0x0 \
        --scale-up --align=left "$poster_path" 2>/dev/null
    for ((i=0; i<IMAGE_HEIGHT; i++)); do echo; done
else
    # Fallback: movie_night.jpg
    if [[ -f "$BLANK_IMG" ]]; then
        kitten icat --transfer-mode=file --stdin=no \
            --place=${IMAGE_WIDTH}x${IMAGE_HEIGHT}@0x0 \
            --scale-up "$BLANK_IMG" 2>/dev/null
    fi
    if [[ -f "$FALLBACK_IMG" ]]; then
        kitten icat --transfer-mode=file --stdin=no \
            --place=${IMAGE_WIDTH}x${IMAGE_HEIGHT}@0x0 \
            --scale-up --align=left "$FALLBACK_IMG" 2>/dev/null
        for ((i=0; i<IMAGE_HEIGHT; i++)); do echo; done
    fi
fi

echo

# --- 10. Get and Display Description ---
DESC_CACHE="${HOME}/.cache/termflix/descriptions"
title_lower=$(echo -n "$title" | tr '[:upper:]' '[:lower:]')
title_hash=$(echo -n "$title_lower" | python3 -c "import sys, hashlib; print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
cached_desc="${DESC_CACHE}/${title_hash}.txt"

description=""
if [[ -f "$cached_desc" ]]; then
    description=$(cat "$cached_desc")
fi

if [[ -n "$description" && "$description" != "null" ]]; then
    echo -e "${WHITE}${description}${RESET}"
    echo
fi

# --- 11. Display Selected Version Info ---
echo -e "${BOLD}${CYAN}Selected Version:${RESET}"
echo -e "${GRAY}────────────────────────────────────────${RESET}"
echo -e "  ${BOLD}Source:${RESET}  ${GREEN}${source}${RESET}"
echo -e "  ${BOLD}Quality:${RESET} ${CYAN}${quality}${RESET}"
echo -e "  ${BOLD}Size:${RESET}    ${YELLOW}${size}${RESET}"
