#!/usr/bin/env bash
#
# Stage 2 Preview Script for KITTY Terminal
# Shows: Poster + Title + Info (for left pane in Stage 2)
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
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
MAGENTA='\033[38;5;213m'
GREEN='\033[38;5;46m'
CYAN='\033[38;5;87m'
YELLOW='\033[38;5;220m'
GRAY='\033[38;5;241m'

# --- 3. Parse Input ---
# Receives: title|source|quality|size|poster_url
IFS='|' read -r title source quality size poster_url <<< "$1"

# --- 4. Display Title ---
echo -e "${BOLD}${MAGENTA}${title}${RESET}"
echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

# --- 5. Display Poster ---
if [[ -n "$poster_url" && "$poster_url" != "N/A" && "$poster_url" != "null" ]]; then
    cache_dir="${HOME}/.cache/termflix/posters"
    mkdir -p "$cache_dir"
    
    filename_hash=$(echo -n "$poster_url" | python3 -c "import sys, hashlib; print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
    poster_path="${cache_dir}/${filename_hash}.jpg"
    
    # Download if not cached
    if [[ ! -f "$poster_path" ]]; then
        curl -sL --max-time 3 "$poster_url" -o "$poster_path" 2>/dev/null
    fi

    # Display Image using Kitty graphics (q=2 for response suppression)
    if [[ -f "$poster_path" && -s "$poster_path" ]]; then
        KITTY_IMAGE_PY="${TERMFLIX_SCRIPTS_DIR}/kitty_image.py"
        
        if [[ -f "$KITTY_IMAGE_PY" ]] && command -v python3 &>/dev/null; then
            python3 "$KITTY_IMAGE_PY" "$poster_path" 40 12
        fi
    fi
fi

echo

# --- 6. Display Info ---
echo -e "${BOLD}Source:${RESET} ${GREEN}[${source}]${RESET}"
echo -e "${BOLD}Quality:${RESET} ${CYAN}${quality}${RESET}"
echo -e "${BOLD}Size:${RESET} ${YELLOW}${size}${RESET}"
