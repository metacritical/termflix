#!/usr/bin/env bash
#
# Termflix Watch History Module
# Track playback progress per torrent hash
#

# Watch history file location
WATCH_HISTORY_DIR="${HOME}/.config/termflix"
WATCH_HISTORY_FILE="${WATCH_HISTORY_DIR}/watch_history.json"

# Initialize watch history
init_watch_history() {
    mkdir -p "$WATCH_HISTORY_DIR"
    if [[ ! -f "$WATCH_HISTORY_FILE" ]]; then
        echo '{}' > "$WATCH_HISTORY_FILE"
    fi
}

# Extract torrent hash from magnet link
extract_torrent_hash() {
    local magnet="$1"
    if [[ "$magnet" =~ btih:([a-fA-F0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]'
    fi
}

# Save watch progress
# Args: hash, position_seconds, duration_seconds, quality, size, title
save_watch_progress() {
    local hash="$1"
    local position="$2"
    local duration="$3"
    local quality="${4:-unknown}"
    local size="${5:-unknown}"
    local title="${6:-unknown}"
    
    init_watch_history
    
    # Calculate percentage
    local percentage=0
    if [[ $duration -gt 0 ]]; then
        percentage=$(( position * 100 / duration ))
    fi
    
    # Mark as completed if >95%
    local completed=false
    [[ $percentage -ge 95 ]] && completed=true
    
    # Get current timestamp
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Update JSON using jq if available, otherwise use simple append
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq --arg hash "$hash" \
           --argjson pos "$position" \
           --argjson dur "$duration" \
           --argjson pct "$percentage" \
           --arg qual "$quality" \
           --arg sz "$size" \
           --arg ttl "$title" \
           --arg ts "$timestamp" \
           --argjson comp "$completed" \
           '.[$hash] = {
               title: $ttl,
               last_position: $pos,
               duration: $dur,
               percentage: $pct,
               quality: $qual,
               size: $sz,
               last_watched: $ts,
               completed: $comp
           }' "$WATCH_HISTORY_FILE" > "$temp_file" && mv "$temp_file" "$WATCH_HISTORY_FILE"
    else
        # Fallback: simple format without JSON
        echo "$hash|$position|$duration|$percentage|$quality|$size|$title|$timestamp|$completed" >> "${WATCH_HISTORY_FILE}.txt"
    fi
}

# Get watch position for a hash (in seconds)
# Returns: seconds (0 if not found)
get_watch_position() {
    local hash="$1"
    
    init_watch_history
    
    if command -v jq &> /dev/null && [[ -f "$WATCH_HISTORY_FILE" ]]; then
        jq -r --arg hash "$hash" '.[$hash].last_position // 0' "$WATCH_HISTORY_FILE" 2>/dev/null || echo "0"
    elif [[ -f "${WATCH_HISTORY_FILE}.txt" ]]; then
        grep "^$hash|" "${WATCH_HISTORY_FILE}.txt" | tail -1 | cut -d'|' -f2 || echo "0"
    else
        echo "0"
    fi
}

# Get watch progress for a hash
# Returns: percentage (empty string if not found)
get_watch_percentage() {
    local hash="$1"
    
    init_watch_history
    
    if command -v jq &> /dev/null && [[ -f "$WATCH_HISTORY_FILE" ]]; then
        jq -r --arg hash "$hash" '
          .[$hash] | if . == null then "" else (.percentage // 0) end
        ' "$WATCH_HISTORY_FILE" 2>/dev/null || echo ""
    elif [[ -f "${WATCH_HISTORY_FILE}.txt" ]]; then
        local line
        line=$(grep "^$hash|" "${WATCH_HISTORY_FILE}.txt" | tail -1 || echo "")
        if [[ -n "$line" ]]; then
            echo "$line" | cut -d'|' -f4
        else
            echo ""
        fi
    else
        echo ""
    fi
}

# Check if hash was previously watched
is_watched() {
    local hash="$1"
    local pct=$(get_watch_percentage "$hash")
    [[ $pct -gt 0 ]]
}

# Generate progress bar string (thin line design)
# Args: percentage (0-100)
generate_progress_bar() {
    local percentage="${1:-0}"
    # Total width: 30 characters for the bar
    local width=30
    local filled=$(( percentage * width / 100 ))
    [[ $filled -lt 0 ]] && filled=0
    [[ $filled -gt $width ]] && filled=$width
    
    # Colors - Pink/Magenta for filled, Gray for empty
    local PINK=$'\033[38;5;205m'      # Hot pink #E879F9
    local GRAY=$'\033[38;5;238m'      # Dark gray
    local WHITE=$'\033[38;5;255m'     # Bright white for percentage
    local RESET=$'\033[0m'
    
    # Use thin line characters (Unicode box drawing)
    # ━ (heavy horizontal) for filled, ─ (light horizontal) for empty
    local bar=""
    for ((i=0; i<width; i++)); do
        if [[ $i -lt $filled ]]; then
            bar+="━"
        else
            bar+="─"
        fi
    done
    
    # Output: colored bar + percentage (0% still shows an empty bar)
    echo "${PINK}${bar:0:$filled}${GRAY}${bar:$filled}${RESET} ${WHITE}${percentage}%${RESET}"
}
