#!/usr/bin/env bash
#
# Stage 2 Preview Script for BLOCK TEXT Mode (xterm-256color)
# Shows: LARGE POSTER ONLY (for left pane in Stage 2)
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

# --- 2. Parse Input ---
# Receives: title|poster_url
IFS='|' read -r title poster_url <<< "$1"

# --- 3. Display Large Poster Only ---
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
            # Large poster: scale to fill left pane (50 cols, proportional height)
            TERM=xterm-256color viu -w 50 -h 30 "$poster_path" 2>/dev/null
        elif command -v chafa &>/dev/null; then
            TERM=xterm-256color chafa --symbols=block --size="50x30" "$poster_path" 2>/dev/null
        fi
    fi
fi
