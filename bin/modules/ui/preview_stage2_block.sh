#!/usr/bin/env bash
#
# Stage 2 Preview Script for BLOCK TEXT Mode (xterm-256color)
# Shows: Large Poster + Title + Basic Info
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
# Receives: title|poster_url (passed as single argument)
input="$1"
IFS='|' read -r title poster_url <<< "$input"

# Debug: Log what we received
# echo "[DEBUG] Input: $input" >&2
# echo "[DEBUG] Title: $title, Poster: $poster_url" >&2

# --- 4. Display Title ---
echo -e "${BOLD}${MAGENTA}${title}${RESET}"
echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

# --- 5. Display Large Poster ---
if [[ -n "$poster_url" && "$poster_url" != "N/A" && "$poster_url" != "null" ]]; then
    cache_dir="${HOME}/.cache/termflix/posters"
    mkdir -p "$cache_dir"
    
    filename_hash=$(echo -n "$poster_url" | python3 -c "import sys, hashlib; print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
    poster_path="${cache_dir}/${filename_hash}.jpg"
    
    # Download if not cached
    if [[ ! -f "$poster_path" ]]; then
        curl -sL --max-time 3 "$poster_url" -o "$poster_path" 2>/dev/null
    fi

    # Display LARGE poster using viu block graphics
    if [[ -f "$poster_path" && -s "$poster_path" ]]; then
        if command -v viu &>/dev/null; then
            # Large poster: scale to fill left pane (90 cols, 50 rows)
            TERM=xterm-256color viu -w 90 -h 50 "$poster_path" 2>/dev/null
        elif command -v chafa &>/dev/null; then
            TERM=xterm-256color chafa --symbols=block --size="90x50" "$poster_path" 2>/dev/null
        fi
    else
        echo -e "${DIM}[Poster loading...]${RESET}"
    fi
else
    # Try to fetch poster on-demand
    POSTER_SCRIPT="${TERMFLIX_SCRIPTS_DIR}/get_poster.py"
    if [[ -f "$POSTER_SCRIPT" ]] && command -v python3 &>/dev/null && [[ -n "$title" ]]; then
        poster_url=$(timeout 3s python3 "$POSTER_SCRIPT" "$title" 2>/dev/null)
        
        if [[ -n "$poster_url" && "$poster_url" != "null" ]]; then
            cache_dir="${HOME}/.cache/termflix/posters"
            mkdir -p "$cache_dir"
            
            filename_hash=$(echo -n "$poster_url" | python3 -c "import sys, hashlib; print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
            poster_path="${cache_dir}/${filename_hash}.jpg"
            
            if [[ ! -f "$poster_path" ]]; then
                curl -sL --max-time 3 "$poster_url" -o "$poster_path" 2>/dev/null
            fi
            
            if [[ -f "$poster_path" && -s "$poster_path" ]]; then
                if command -v viu &>/dev/null; then
                    TERM=xterm-256color viu -w 90 -h 50 "$poster_path" 2>/dev/null
                fi
            fi
        fi
    fi
fi

echo
echo -e "${DIM}Select a version from the picker →${RESET}"
