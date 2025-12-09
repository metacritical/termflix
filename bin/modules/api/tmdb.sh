#!/usr/bin/env bash
#
# Termflix TMDB API Module
# Fetches movie metadata (descriptions, ratings, etc.) from The Movie Database
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_TMDB_LOADED:-}" ]] && return 0
_TERMFLIX_TMDB_LOADED=1

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

# Source config module if available
TMDB_SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${TMDB_SCRIPT_DIR}/../core/config.sh" ]]; then
    source "${TMDB_SCRIPT_DIR}/../core/config.sh"
fi

# Get API key: config file first, then environment variable
_get_api_key() {
    local key=""
    
    # Try config file first
    if command -v get_tmdb_api_key &>/dev/null; then
        key=$(get_tmdb_api_key)
    fi
    
    # Fallback to environment variable
    [[ -z "$key" ]] && key="${TMDB_API_KEY:-}"
    
    echo "$key"
}

TMDB_API_KEY="${TMDB_API_KEY:-$(_get_api_key)}"
TMDB_BASE_URL="https://api.themoviedb.org/3"
TMDB_CACHE_DIR="${HOME}/.cache/termflix/tmdb"
TMDB_CACHE_TTL=$((7 * 24 * 60 * 60))  # 7 days in seconds

# ═══════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Generate cache key from title and year
_tmdb_cache_key() {
    local title="$1"
    local year="${2:-}"
    local normalized
    
    # Normalize: lowercase, remove special chars
    normalized=$(echo "${title}${year}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
    
    # Generate MD5 hash
    if command -v md5 &>/dev/null; then
        echo -n "$normalized" | md5
    elif command -v md5sum &>/dev/null; then
        echo -n "$normalized" | md5sum | cut -d' ' -f1
    else
        # Fallback: use python
        python3 -c "import hashlib; print(hashlib.md5('${normalized}'.encode()).hexdigest())"
    fi
}

# Check if cache is valid (exists and not expired)
_tmdb_cache_valid() {
    local cache_file="$1"
    
    [[ ! -f "$cache_file" ]] && return 1
    
    local file_age=$(( $(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || stat -c%Y "$cache_file" 2>/dev/null) ))
    [[ $file_age -lt $TMDB_CACHE_TTL ]]
}

# URL encode a string
_urlencode() {
    python3 -c "import urllib.parse; print(urllib.parse.quote('$1'))"
}

# ═══════════════════════════════════════════════════════════════
# API FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Search TMDB for a movie by title and optional year
# Returns: JSON with id, title, overview, release_date, vote_average
search_tmdb_movie() {
    local title="$1"
    local year="${2:-}"
    
    # Check API key
    if [[ -z "$TMDB_API_KEY" ]]; then
        echo '{"error": "No TMDB API key configured"}'
        return 1
    fi
    
    # Create cache directory
    mkdir -p "$TMDB_CACHE_DIR"
    
    # Check cache
    local cache_key=$(_tmdb_cache_key "$title" "$year")
    local cache_file="${TMDB_CACHE_DIR}/${cache_key}.json"
    
    if _tmdb_cache_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi
    
    # Build API URL
    local encoded_title=$(_urlencode "$title")
    local url="${TMDB_BASE_URL}/search/movie?api_key=${TMDB_API_KEY}&query=${encoded_title}"
    
    [[ -n "$year" ]] && url="${url}&year=${year}"
    
    # Make API request
    local response
    response=$(curl -sL --max-time 5 "$url" 2>/dev/null)
    
    if [[ -z "$response" ]]; then
        echo '{"error": "TMDB API request failed"}'
        return 1
    fi
    
    # Extract first result
    local result
    result=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('results') and len(data['results']) > 0:
        r = data['results'][0]
        print(json.dumps({
            'id': r.get('id'),
            'title': r.get('title'),
            'overview': r.get('overview', ''),
            'release_date': r.get('release_date', ''),
            'vote_average': r.get('vote_average', 0),
            'poster_path': r.get('poster_path', '')
        }))
    else:
        print(json.dumps({'error': 'No results found'}))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null)
    
    # Cache result
    echo "$result" > "$cache_file"
    echo "$result"
}

# Get movie metadata (search + fetch in one call)
# Returns: JSON with movie details
get_movie_metadata() {
    local title="$1"
    local year="${2:-}"
    
    search_tmdb_movie "$title" "$year"
}

# Extract description from metadata JSON
# Usage: description=$(echo "$metadata" | extract_description)
extract_description() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('overview', 'No description available.'))
except:
    print('No description available.')
"
}

# Extract rating from metadata JSON
extract_rating() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    rating = data.get('vote_average', 0)
    if rating > 0:
        print(f'{rating:.1f}/10')
    else:
        print('N/A')
except:
    print('N/A')
"
}

# ═══════════════════════════════════════════════════════════════
# CONVENIENCE FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Fetch just the description for a movie
# Returns: Plain text description
fetch_movie_description() {
    local title="$1"
    local year="${2:-}"
    
    local metadata
    metadata=$(get_movie_metadata "$title" "$year")
    
    echo "$metadata" | extract_description
}

# Check if TMDB is configured
tmdb_configured() {
    [[ -n "$TMDB_API_KEY" ]]
}

# ═══════════════════════════════════════════════════════════════
# EXPORTS
# ═══════════════════════════════════════════════════════════════

export -f search_tmdb_movie get_movie_metadata
export -f extract_description extract_rating
export -f fetch_movie_description tmdb_configured
