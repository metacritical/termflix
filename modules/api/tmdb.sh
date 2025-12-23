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

# Use centralized config - get_tmdb_api_key from config.sh
if command -v get_tmdb_api_key &>/dev/null; then
    TMDB_API_KEY="${TMDB_API_KEY:-$(get_tmdb_api_key)}"
fi

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
    if [[ -n "$1" ]]; then
        python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$1"
    else
        python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read().strip()))"
    fi
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
# TV SHOW FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Search TMDB for a TV show by name
# Returns: JSON with id, name, overview, first_air_date, vote_average, poster_path
search_tmdb_tv() {
    local name="$1"
    local year="${2:-}"
    
    # Check API key
    if [[ -z "$TMDB_API_KEY" ]]; then
        echo '{"error": "No TMDB API key configured"}'
        return 1
    fi
    
    # Create cache directory
    mkdir -p "$TMDB_CACHE_DIR"
    
    # Check cache (use different prefix for TV)
    local cache_key=$(_tmdb_cache_key "tv_${name}" "$year")
    local cache_file="${TMDB_CACHE_DIR}/${cache_key}.json"
    
    if _tmdb_cache_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi
    
    # Build API URL
    local encoded_name=$(_urlencode "$name")
    local url="${TMDB_BASE_URL}/search/tv?api_key=${TMDB_API_KEY}&query=${encoded_name}"
    
    [[ -n "$year" ]] && url="${url}&first_air_date_year=${year}"
    
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
            'name': r.get('name'),
            'overview': r.get('overview', ''),
            'first_air_date': r.get('first_air_date', ''),
            'vote_average': r.get('vote_average', 0),
            'poster_path': r.get('poster_path', ''),
            'media_type': 'tv'
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

# Find media by IMDB ID (works for both movies and TV shows)
# Returns: JSON with media details
find_by_imdb_id() {
    local imdb_id="$1"
    
    # Check API key
    if [[ -z "$TMDB_API_KEY" ]]; then
        echo '{"error": "No TMDB API key configured"}'
        return 1
    fi
    
    # Validate IMDB ID format
    if [[ ! "$imdb_id" =~ ^tt[0-9]+ ]]; then
        echo '{"error": "Invalid IMDB ID format"}'
        return 1
    fi
    
    # Create cache directory
    mkdir -p "$TMDB_CACHE_DIR"
    
    # Check cache
    local cache_key=$(_tmdb_cache_key "imdb_${imdb_id}" "")
    local cache_file="${TMDB_CACHE_DIR}/${cache_key}.json"
    
    if _tmdb_cache_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi
    
    # Use /find endpoint with IMDB ID
    local url="${TMDB_BASE_URL}/find/${imdb_id}?api_key=${TMDB_API_KEY}&external_source=imdb_id"
    
    local response
    response=$(curl -sL --max-time 5 "$url" 2>/dev/null)
    
    if [[ -z "$response" ]]; then
        echo '{"error": "TMDB API request failed"}'
        return 1
    fi
    
    # Extract result (check both movie and TV results)
    local result
    result=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    
    # Check movie results first
    if data.get('movie_results') and len(data['movie_results']) > 0:
        r = data['movie_results'][0]
        print(json.dumps({
            'id': r.get('id'),
            'title': r.get('title'),
            'name': r.get('title'),  # Alias for consistency
            'overview': r.get('overview', ''),
            'release_date': r.get('release_date', ''),
            'vote_average': r.get('vote_average', 0),
            'poster_path': r.get('poster_path', ''),
            'media_type': 'movie'
        }))
    # Check TV results
    elif data.get('tv_results') and len(data['tv_results']) > 0:
        r = data['tv_results'][0]
        print(json.dumps({
            'id': r.get('id'),
            'name': r.get('name'),
            'title': r.get('name'),  # Alias for consistency
            'overview': r.get('overview', ''),
            'first_air_date': r.get('first_air_date', ''),
            'vote_average': r.get('vote_average', 0),
            'poster_path': r.get('poster_path', ''),
            'media_type': 'tv'
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

# Get TV show metadata (search + fetch in one call)
# Returns: JSON with TV show details
get_tv_metadata() {
    local name="$1"
    local year="${2:-}"
    
    search_tmdb_tv "$name" "$year"
}

# Get full TV show details (including seasons)
get_tv_details() {
    local tv_id="$1"
    
    if [[ -z "$TMDB_API_KEY" ]]; then
        echo '{"error": "No TMDB API key configured"}'
        return 1
    fi
    
    # Check cache
    local cache_key=$(_tmdb_cache_key "tv_details_${tv_id}" "")
    local cache_file="${TMDB_CACHE_DIR}/${cache_key}.json"
    
    if _tmdb_cache_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi
    
    local url="${TMDB_BASE_URL}/tv/${tv_id}?api_key=${TMDB_API_KEY}"
    local response=$(curl -sL --max-time 5 "$url" 2>/dev/null)
    
    if [[ -n "$response" ]]; then
        echo "$response" > "$cache_file"
        echo "$response"
    else
        echo '{"error": "TMDB API request failed"}'
        return 1
    fi
}

# Get TV season details (including episodes)
get_tv_season_details() {
    local tv_id="$1"
    local season_number="$2"
    
    if [[ -z "$TMDB_API_KEY" ]]; then
        echo '{"error": "No TMDB API key configured"}'
        return 1
    fi
    
    # Check cache
    local cache_key=$(_tmdb_cache_key "tv_season_${tv_id}_s${season_number}" "")
    local cache_file="${TMDB_CACHE_DIR}/${cache_key}.json"
    
    if _tmdb_cache_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi
    
    local url="${TMDB_BASE_URL}/tv/${tv_id}/season/${season_number}?api_key=${TMDB_API_KEY}"
    local response=$(curl -sL --max-time 5 "$url" 2>/dev/null)
    
    if [[ -n "$response" ]]; then
        echo "$response" > "$cache_file"
        echo "$response"
    else
        echo '{"error": "TMDB API request failed"}'
        return 1
    fi
}

# Get TV episode info
# Usage: get_tv_episode_info <tv_id> <season> <episode>
get_tv_episode_info() {
    local tv_id="$1"
    local season="$2"
    local episode="$3"
    
    if [[ -z "$TMDB_API_KEY" ]]; then
        echo '{"error": "No TMDB API key configured"}'
        return 1
    fi
    
    # Create cache directory
    mkdir -p "$TMDB_CACHE_DIR"
    
    # Check cache
    local cache_key=$(_tmdb_cache_key "ep_${tv_id}_s${season}e${episode}" "")
    local cache_file="${TMDB_CACHE_DIR}/${cache_key}.json"
    
    if _tmdb_cache_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi
    
    local url="${TMDB_BASE_URL}/tv/${tv_id}/season/${season}/episode/${episode}?api_key=${TMDB_API_KEY}"
    
    local response
    response=$(curl -sL --max-time 5 "$url" 2>/dev/null)
    
    if [[ -z "$response" ]]; then
        echo '{"error": "TMDB API request failed"}'
        return 1
    fi
    
    # Extract episode info
    local result
    result=$(echo "$response" | python3 -c "
import sys, json
try:
    r = json.load(sys.stdin)
    if r.get('id'):
        print(json.dumps({
            'id': r.get('id'),
            'name': r.get('name', ''),
            'overview': r.get('overview', ''),
            'air_date': r.get('air_date', ''),
            'episode_number': r.get('episode_number', 0),
            'season_number': r.get('season_number', 0),
            'vote_average': r.get('vote_average', 0),
            'still_path': r.get('still_path', '')
        }))
    else:
        print(json.dumps({'error': 'Episode not found'}))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null)
    
    # Cache result
    echo "$result" > "$cache_file"
    echo "$result"
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

# Fetch description for a TV show
fetch_tv_description() {
    local name="$1"
    local year="${2:-}"
    
    local metadata
    metadata=$(get_tv_metadata "$name" "$year")
    
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
export -f search_tmdb_tv get_tv_metadata find_by_imdb_id get_tv_episode_info
export -f get_tv_details get_tv_season_details
export -f extract_description extract_rating
export -f fetch_movie_description fetch_tv_description tmdb_configured
