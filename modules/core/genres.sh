#!/usr/bin/env bash
#
# Termflix Genre Styling Module
# Provides styled genre display with mood-based colors and emojis
#
# Usage:
#   source genres.sh
#   style_genre "Action"         # Returns styled "Action 💥" with color
#   style_genres "Action, Drama" # Returns styled comma-separated list
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_GENRES_LOADED:-}" ]] && return 0
_TERMFLIX_GENRES_LOADED=1

# Resolve script directory
_GENRE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# genres.sh is in /modules/core/, genres.json is in /data/
_GENRES_JSON="${_GENRE_SCRIPT_DIR}/../../data/genres.json"

# ANSI color helpers
_hex_to_ansi() {
    local hex="$1"
    hex="${hex#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
}

# ANSI background color helper
_hex_to_ansi_bg() {
    local hex="$1"
    hex="${hex#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    printf '\033[48;2;%d;%d;%dm' "$r" "$g" "$b"
}

# Get emoji for a genre
get_genre_emoji() {
    local genre="$1"
    if [[ -f "$_GENRES_JSON" ]]; then
        python3 -c "
import json, sys
with open('$_GENRES_JSON') as f:
    data = json.load(f)
    emoji = data.get('genres', {}).get('$genre', {}).get('emoji', '')
    print(emoji)
" 2>/dev/null
    fi
}

# Get color for a genre
get_genre_color() {
    local genre="$1"
    if [[ -f "$_GENRES_JSON" ]]; then
        python3 -c "
import json, sys
with open('$_GENRES_JSON') as f:
    data = json.load(f)
    color = data.get('genres', {}).get('$genre', {}).get('color', '')
    print(color)
" 2>/dev/null
    fi
}

# Style a single genre as pill button with colored background + white text + emoji inside
style_genre() {
    local genre="$1"
    local emoji color bg_ansi reset white_fg
    
    emoji=$(get_genre_emoji "$genre")
    color=$(get_genre_color "$genre")
    reset=$'\033[0m'
    white_fg=$'\033[97m'  # Bright white foreground
    
    if [[ -n "$color" ]]; then
        bg_ansi=$(_hex_to_ansi_bg "$color")
        # Pill with colored background, emoji INSIDE
        echo -n "${bg_ansi}${white_fg} ${genre}"
        [[ -n "$emoji" ]] && echo -n " ${emoji}"
        echo -n " ${reset}"
    else
        echo -n " $genre"
        [[ -n "$emoji" ]] && echo -n " ${emoji}"
        echo -n " "
    fi
}

# Style a comma-separated list of genres as pill buttons
# Input: "Action, Drama, Thriller"
# Output: "▓ Action 💥 ▓  ▓ Drama 🎭 ▓  ..."
style_genres() {
    local genres_str="$1"
    local result=""
    local first=true
    
    # Split by comma
    IFS=',' read -ra genres_arr <<< "$genres_str"
    
    for genre in "${genres_arr[@]}"; do
        # Trim whitespace
        genre=$(echo "$genre" | xargs)
        [[ -z "$genre" ]] && continue
        
        if [[ "$first" == true ]]; then
            first=false
        else
            result+=" "
        fi
        
        result+=$(style_genre "$genre")
    done
    
    echo -e "$result"
}

# Export functions
export -f get_genre_emoji
export -f get_genre_color
export -f style_genre
export -f style_genres
