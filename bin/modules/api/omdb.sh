#!/usr/bin/env bash
#
# Termflix OMDB API Module (Simplified Thin Wrapper)
# Routes to Python backend (lib/termflix/scripts/api.py) when enabled
# Legacy Bash+curl implementation available as fallback
#
# Refactored: December 2025 - Simplified after Python backend promotion

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_OMDB_LOADED:-}" ]] && return 0
_TERMFLIX_OMDB_LOADED=1

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

# Source config module
OMDB_SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${OMDB_SCRIPT_DIR}/../core/config.sh" ]] && source "${OMDB_SCRIPT_DIR}/../core/config.sh"

# Get API key from centralized config
if command -v get_omdb_api_key &>/dev/null; then
    OMDB_API_KEY="${OMDB_API_KEY:-$(get_omdb_api_key)}"
fi

OMDB_BASE_URL="http://www.omdbapi.com"
OMDB_CACHE_DIR="${HOME}/.cache/termflix/omdb"
OMDB_CACHE_TTL=$((7 * 24 * 60 * 60))  # 7 days

# ═══════════════════════════════════════════════════════════════
# PRIMARY API FUNCTIONS (Python Backend)
# ═══════════════════════════════════════════════════════════════

# Search OMDB for a movie by title and optional year
# Returns: JSON with Title, Year, Plot, Poster, Ratings, etc.
search_omdb_movie() {
    local title="$1"
    local year="${2:-}"
    
    # Use Python API backend (default since Dec 2025)
    if command -v use_python_api &>/dev/null && use_python_api; then
        local api_script="${TERMFLIX_LIB_DIR:-${OMDB_SCRIPT_DIR}/../../../lib/termflix}/scripts/api.py"
        
        if [[ -f "$api_script" ]] && command -v python3 &>/dev/null; then
            if [[ -n "$year" ]]; then
                python3 "$api_script" omdb "$title" "$year" 2>/dev/null && return 0
            else
                python3 "$api_script" omdb "$title" 2>/dev/null && return 0
            fi
        fi
    fi
    
    # Fallback to legacy Bash implementation
    _legacy_search_omdb_movie "$title" "$year"
}

# Get movie metadata (convenience wrapper)
get_omdb_metadata() {
    search_omdb_movie "$@"
}

# Fetch just the description for a movie
fetch_omdb_description() {
    local title="$1"
    local year="$2:-}"
    
    get_omdb_metadata "$title" "$year" | extract_omdb_plot
}

# Check if OMDB is configured
omdb_configured() {
    [[ -n "$OMDB_API_KEY" ]]
}

# ═══════════════════════════════════════════════════════════════
# JSON EXTRACTION HELPERS
# ═══════════════════════════════════════════════════════════════

# Extract plot/description from JSON
extract_omdb_plot() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('plot', '') or data.get('Plot', ''), end='')
except: pass
"
}

# Extract rating from JSON
extract_omdb_rating() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    rating = data.get('rating', data.get('imdbRating', 'N/A'))
    print(rating if rating != 'N/A' else 'N/A', end='')
except: print('N/A', end='')
"
}

# Extract poster URL from JSON
extract_omdb_poster() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    poster = data.get('poster', data.get('Poster', ''))
    print(poster if poster and poster != 'N/A' else '', end='')
except: pass
"
}

# Extract genre from JSON
extract_omdb_genre() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('genre', data.get('Genre', 'N/A')), end='')
except: print('N/A', end='')
"
}

# Extract runtime from JSON
extract_omdb_runtime() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('runtime', data.get('Runtime', 'N/A')), end='')
except: print('N/A', end='')
"
}

# Extract year from JSON
extract_omdb_year() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    year  = data.get('year', data.get('Year', 'N/A'))
    print(str(year) if year and year != 'N/A' else 'N/A', end='')
except: print('N/A', end='')
"
}

# ═══════════════════════════════════════════════════════════════
# LEGACY BASH IMPLEMENTATION (Fallback Only)
# ═══════════════════════════════════════════════════════════════
# NOTE: This code is kept for compatibility when Python backend unavailable.
# It is marked as legacy and will only run if Python API fails or is disabled.

_omdb_cache_key() {
    local normalized=$(echo "${1}${2:-}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
    if command -v md5 &>/dev/null; then
        echo -n "$normalized" | md5
    elif command -v md5sum &>/dev/null; then
        echo -n "$normalized" | md5sum | cut -d' ' -f1
    else
        python3 -c "import hashlib; print(hashlib.md5('${normalized}'.encode()).hexdigest())"
    fi
}

_omdb_cache_valid() {
    [[ ! -f "$1" ]] && return 1
    local file_age=$(( $(date +%s) - $(stat -f%m "$1" 2>/dev/null || stat -c%Y "$1" 2>/dev/null) ))
    [[ $file_age -lt $OMDB_CACHE_TTL ]]
}

_omdb_urlencode() {
    python3 -c "import urllib.parse; print(urllib.parse.quote('$1'))"
}

_legacy_search_omdb_movie() {
    local title="$1"
    local year="${2:-}"
    
    # Check API key
    if [[ -z "$OMDB_API_KEY" ]]; then
        echo '{"Error": "No OMDB API key configured", "Response": "False"}'
        return 1
    fi
    
    mkdir -p "$OMDB_CACHE_DIR"
    
    # Check cache
    local cache_key=$(_omdb_cache_key "$title" "$year")
    local cache_file="${OMDB_CACHE_DIR}/${cache_key}.json"
    
    if _omdb_cache_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi
    
    # API request
    local clean_title=$(echo "$title" | sed 's/[[:space:]_]/./g' | sed 's/\.\..*/./g')
    local encoded_title=$(_omdb_urlencode "$clean_title")
    local url="${OMDB_BASE_URL}/?apikey=${OMDB_API_KEY}&t=${encoded_title}&type=movie&plot=short"
    [[ -n "$year" ]] && url="${url}&y=${year}"
    
    local response=$(curl -sL --max-time 5 "$url" 2>/dev/null)
    
    if [[ -n "$response" ]] && echo "$response" | grep -q '"Response":"True"'; then
        echo "$response" > "$cache_file"
        echo "$response"
        return 0
    fi
    
    # Fallback: search API
    local search_url="${OMDB_BASE_URL}/?apikey=${OMDB_API_KEY}&s=${encoded_title}&type=movie"
    [[ -n "$year" ]] && search_url="${search_url}&y=${year}"
    
    local search_response=$(curl -sL --max-time 5 "$search_url" 2>/dev/null)
    
    if [[ -n "$search_response" ]] && echo "$search_response" | grep -q '"Response":"True"'; then
        local imdb_id=$(echo "$search_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('Search'):
        print(data['Search'][0].get('imdbID', ''))
except: pass
" 2>/dev/null)
        
        if [[ -n "$imdb_id" ]]; then
            response=$(curl -sL --max-time 5 "${OMDB_BASE_URL}/?apikey=${OMDB_API_KEY}&i=${imdb_id}&plot=short" 2>/dev/null)
            if [[ -n "$response" ]] && echo "$response" | grep -q '"Response":"True"'; then
                echo "$response" > "$cache_file"
                echo "$response"
                return 0
            fi
        fi
    fi
    
    echo '{"Error": "Movie not found", "Response": "False"}'
    return 1
}

# ═══════════════════════════════════════════════════════════════
# EXPORTS
# ═══════════════════════════════════════════════════════════════

export -f search_omdb_movie get_omdb_metadata fetch_omdb_description omdb_configured
export -f extract_omdb_plot extract_omdb_rating extract_omdb_poster
export -f extract_omdb_genre extract_omdb_runtime extract_omdb_year
