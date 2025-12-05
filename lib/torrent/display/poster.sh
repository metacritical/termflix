#!/bin/bash
# Poster/image handling functions

# Source colors if not already defined
if [ -z "$CYAN" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/colors.sh" 2>/dev/null || true
fi

# Check for viu (optional, for displaying images on Mac)
check_viu() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if ! command -v viu &> /dev/null; then
            return 1
        fi
    fi
    command -v viu &> /dev/null
}

# Cleanup poster images
cleanup_posters() {
    local temp_dir="${TMPDIR:-/tmp}/torrent_posters_$$"
    rm -rf "$temp_dir" 2>/dev/null
}

# Fetch poster from OMDB with caching
# Note: get_omdb_api_key must be exported from the main script
fetch_omdb_poster() {
    local title="$1"
    local year="$2"
    
    if [ -z "$title" ]; then
        echo "N/A"
        return 1
    fi
    
    # Get API Key (must be exported from main script)
    local api_key=$(get_omdb_api_key)
    if [ -z "$api_key" ] || [ "$api_key" = "N/A" ]; then
        echo "N/A"
        return 1
    fi
    
    # Create cache directory
    local cache_dir="${HOME}/.cache/torrent/omdb"
    mkdir -p "$cache_dir" 2>/dev/null
    
    # Create cache key from title and year
    local clean_title=$(echo "$title" | tr -cd '[:alnum:]')
    local cache_key="${clean_title}_${year}"
    local cache_file="${cache_dir}/${cache_key}.json"
    
    # Check cache first
    if [ -f "$cache_file" ]; then
        local poster=$(cat "$cache_file" | grep -o '"Poster":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$poster" ] && [ "$poster" != "N/A" ]; then
            echo "$poster"
            return 0
        fi
        # If cached but N/A, return N/A (don't retry immediately)
        echo "N/A"
        return 0
    fi
    
    # Fetch from API
    # Encode title for URL (use jq if available, otherwise fallback)
    local encoded_title
    if command -v jq &> /dev/null; then
        encoded_title=$(echo "$title" | jq -sRr @uri | tr -d '\r\n')
    else
        encoded_title=$(echo "$title" | sed 's/ /%20/g')
    fi
    
    local api_url="http://www.omdbapi.com/?apikey=${api_key}&t=${encoded_title}"
    if [ -n "$year" ]; then
        api_url="${api_url}&y=${year}"
    fi
    
    if command -v curl &> /dev/null; then
        local response=$(curl -s --max-time 3 "$api_url" 2>/dev/null)
        
        if [ -n "$response" ]; then
            # Save to cache
            echo "$response" > "$cache_file"
            
            # Extract poster
            local poster=$(echo "$response" | grep -o '"Poster":"[^"]*"' | cut -d'"' -f4)
            if [ -n "$poster" ] && [ "$poster" != "N/A" ]; then
                echo "$poster"
                return 0
            fi
        fi
    fi
    
    echo "N/A"
    return 1
}
