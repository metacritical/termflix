#!/usr/bin/env bash
#
# Termflix OMDB API Module
# Fetches movie metadata from the Open Movie Database (OMDb)
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_OMDB_LOADED:-}" ]] && return 0
_TERMFLIX_OMDB_LOADED=1

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

# Source config module if available
OMDB_SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${OMDB_SCRIPT_DIR}/../core/config.sh" ]]; then
    source "${OMDB_SCRIPT_DIR}/../core/config.sh"
fi

# Use centralized config - get_omdb_api_key from config.sh
if command -v get_omdb_api_key &>/dev/null; then
    OMDB_API_KEY="${OMDB_API_KEY:-$(get_omdb_api_key)}"
fi

OMDB_BASE_URL="http://www.omdbapi.com"
OMDB_CACHE_DIR="${HOME}/.cache/termflix/omdb"
OMDB_CACHE_TTL=$((7 * 24 * 60 * 60))  # 7 days in seconds

# ═══════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Generate cache key from title and year
_omdb_cache_key() {
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
        python3 -c "import hashlib; print(hashlib.md5('${normalized}'.encode()).hexdigest())"
    fi
}

# Check if cache is valid
_omdb_cache_valid() {
    local cache_file="$1"
    
    [[ ! -f "$cache_file" ]] && return 1
    
    local file_age=$(( $(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || stat -c%Y "$cache_file" 2>/dev/null) ))
    [[ $file_age -lt $OMDB_CACHE_TTL ]]
}

# URL encode a string
_omdb_urlencode() {
    python3 -c "import urllib.parse; print(urllib.parse.quote('$1'))"
}

# ═══════════════════════════════════════════════════════════════
# API FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Search OMDB for a movie by title and optional year
# Returns: JSON with Title, Year, Plot, Poster, Ratings, etc.
search_omdb_movie() {
    local title="$1"
    local year="${2:-}"
    
    # Check API key
    if [[ -z "$OMDB_API_KEY" ]]; then
        echo '{"Error": "No OMDB API key configured", "Response": "False"}'
        return 1
    fi
    
    # Create cache directory
    mkdir -p "$OMDB_CACHE_DIR"
    
    # Check cache
    local cache_key=$(_omdb_cache_key "$title" "$year")
    local cache_file="${OMDB_CACHE_DIR}/${cache_key}.json"
    
    if _omdb_cache_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi
    
    # Clean title: replace spaces/underscores with dots for OMDB compatibility
    local clean_title=$(echo "$title" | sed 's/[[:space:]_]/./g' | sed 's/\.\.*/./g')
    
    # Build API URL - try by title first (t=)
    local encoded_title=$(_omdb_urlencode "$clean_title")
    local url="${OMDB_BASE_URL}/?apikey=${OMDB_API_KEY}&t=${encoded_title}&type=movie&plot=short"
    
    [[ -n "$year" ]] && url="${url}&y=${year}"
    
    # Make API request
    local response
    response=$(curl -sL --max-time 5 "$url" 2>/dev/null)
    
    # Check if title search succeeded
    if [[ -n "$response" ]] && echo "$response" | grep -q '"Response":"True"'; then
        echo "$response" > "$cache_file"
        echo "$response"
        return 0
    fi
    
    # Fallback: try search API (s=) for fuzzy matching
    local search_url="${OMDB_BASE_URL}/?apikey=${OMDB_API_KEY}&s=${encoded_title}&type=movie"
    [[ -n "$year" ]] && search_url="${search_url}&y=${year}"
    
    local search_response
    search_response=$(curl -sL --max-time 5 "$search_url" 2>/dev/null)
    
    if [[ -n "$search_response" ]] && echo "$search_response" | grep -q '"Response":"True"'; then
        # Get first result's IMDB ID and fetch full details
        local imdb_id
        imdb_id=$(echo "$search_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('Search'):
        print(data['Search'][0].get('imdbID', ''))
except:
    pass
" 2>/dev/null)
        
        if [[ -n "$imdb_id" ]]; then
            # Fetch full details by IMDB ID
            response=$(curl -sL --max-time 5 "${OMDB_BASE_URL}/?apikey=${OMDB_API_KEY}&i=${imdb_id}&plot=short" 2>/dev/null)
            
            if [[ -n "$response" ]] && echo "$response" | grep -q '"Response":"True"'; then
                echo "$response" > "$cache_file"
                echo "$response"
                return 0
            fi
        fi
    fi
    
    # Return error response
    echo '{"Error": "Movie not found", "Response": "False"}'
    return 1
}

# Get movie metadata (wrapper)
get_omdb_metadata() {
    local title="$1"
    local year="${2:-}"
    
    search_omdb_movie "$title" "$year"
}

# Extract plot/description from OMDB response
extract_omdb_plot() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('Response') == 'True':
        print(data.get('Plot', ''))
    else:
        print('')
except:
    print('')
"
}

# Extract rating from OMDB response (IMDB rating)
extract_omdb_rating() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('Response') == 'True':
        rating = data.get('imdbRating', 'N/A')
        print(f'{rating}/10' if rating != 'N/A' else 'N/A')
    else:
        print('N/A')
except:
    print('N/A')
"
}

# Extract poster URL from OMDB response
extract_omdb_poster() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('Response') == 'True':
        poster = data.get('Poster', 'N/A')
        print(poster if poster != 'N/A' else '')
    else:
        print('')
except:
    print('')
"
}

# Extract genre from OMDB response
extract_omdb_genre() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('Response') == 'True':
        print(data.get('Genre', 'N/A'))
    else:
        print('N/A')
except:
    print('N/A')
"
}

# Extract runtime from OMDB response
extract_omdb_runtime() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('Response') == 'True':
        print(data.get('Runtime', 'N/A'))
    else:
        print('N/A')
except:
    print('N/A')
"
}

# Extract year from OMDB response
extract_omdb_year() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('Response') == 'True':
        print(data.get('Year', 'N/A'))
    else:
        print('N/A')
except:
    print('N/A')
"
}

# Extract rated (content rating) from OMDB response
extract_omdb_rated() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('Response') == 'True':
        print(data.get('Rated', 'N/A'))
    else:
        print('N/A')
except:
    print('N/A')
"
}

# ═══════════════════════════════════════════════════════════════
# TV SERIES FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Search OMDB for a TV series by name
# Returns: JSON with Title, Year, Plot, Poster, Ratings, etc.
search_omdb_series() {
    local title="$1"
    local year="${2:-}"
    
    # Check API key
    if [[ -z "$OMDB_API_KEY" ]]; then
        echo '{"Error": "No OMDB API key configured", "Response": "False"}'
        return 1
    fi
    
    # Create cache directory
    mkdir -p "$OMDB_CACHE_DIR"
    
    # Check cache (use series prefix)
    local cache_key=$(_omdb_cache_key "series_${title}" "$year")
    local cache_file="${OMDB_CACHE_DIR}/${cache_key}.json"
    
    if _omdb_cache_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi
    
    # Clean title
    local clean_title=$(echo "$title" | sed 's/[[:space:]_]/./g' | sed 's/\.\.*/./g')
    
    # Build API URL with type=series
    local encoded_title=$(_omdb_urlencode "$clean_title")
    local url="${OMDB_BASE_URL}/?apikey=${OMDB_API_KEY}&t=${encoded_title}&type=series&plot=short"
    
    [[ -n "$year" ]] && url="${url}&y=${year}"
    
    # Make API request
    local response
    response=$(curl -sL --max-time 5 "$url" 2>/dev/null)
    
    # Check if request succeeded
    if [[ -n "$response" ]] && echo "$response" | grep -q '"Response":"True"'; then
        echo "$response" > "$cache_file"
        echo "$response"
        return 0
    fi
    
    # Fallback: try search API
    local search_url="${OMDB_BASE_URL}/?apikey=${OMDB_API_KEY}&s=${encoded_title}&type=series"
    [[ -n "$year" ]] && search_url="${search_url}&y=${year}"
    
    local search_response
    search_response=$(curl -sL --max-time 5 "$search_url" 2>/dev/null)
    
    if [[ -n "$search_response" ]] && echo "$search_response" | grep -q '"Response":"True"'; then
        # Get first result's IMDB ID
        local imdb_id
        imdb_id=$(echo "$search_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('Search'):
        print(data['Search'][0].get('imdbID', ''))
except:
    pass
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
    
    echo '{"Error": "Series not found", "Response": "False"}'
    return 1
}

# Search OMDB for a specific episode
# Returns: JSON with episode details
search_omdb_episode() {
    local title="$1"
    local season="$2"
    local episode="$3"
    
    # Check API key
    if [[ -z "$OMDB_API_KEY" ]]; then
        echo '{"Error": "No OMDB API key configured", "Response": "False"}'
        return 1
    fi
    
    # Create cache directory
    mkdir -p "$OMDB_CACHE_DIR"
    
    # Check cache
    local cache_key=$(_omdb_cache_key "ep_${title}_s${season}e${episode}" "")
    local cache_file="${OMDB_CACHE_DIR}/${cache_key}.json"
    
    if _omdb_cache_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi
    
    # Clean title
    local clean_title=$(echo "$title" | sed 's/[[:space:]_]/./g' | sed 's/\.\.*/./g')
    local encoded_title=$(_omdb_urlencode "$clean_title")
    
    # Build URL with season and episode
    local url="${OMDB_BASE_URL}/?apikey=${OMDB_API_KEY}&t=${encoded_title}&Season=${season}&Episode=${episode}&plot=short"
    
    local response
    response=$(curl -sL --max-time 5 "$url" 2>/dev/null)
    
    if [[ -n "$response" ]] && echo "$response" | grep -q '"Response":"True"'; then
        echo "$response" > "$cache_file"
        echo "$response"
        return 0
    fi
    
    echo '{"Error": "Episode not found", "Response": "False"}'
    return 1
}

# Get series metadata (wrapper)
get_omdb_series_metadata() {
    local title="$1"
    local year="${2:-}"
    
    search_omdb_series "$title" "$year"
}

# Extract series total seasons
extract_omdb_total_seasons() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('Response') == 'True':
        print(data.get('totalSeasons', 'N/A'))
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
fetch_omdb_description() {
    local title="$1"
    local year="${2:-}"
    
    local metadata
    metadata=$(get_omdb_metadata "$title" "$year")
    
    echo "$metadata" | extract_omdb_plot
}

# Fetch description for a TV series
fetch_omdb_series_description() {
    local title="$1"
    local year="${2:-}"
    
    local metadata
    metadata=$(get_omdb_series_metadata "$title" "$year")
    
    echo "$metadata" | extract_omdb_plot
}

# Check if OMDB is configured
omdb_configured() {
    [[ -n "$OMDB_API_KEY" ]]
}

# ═══════════════════════════════════════════════════════════════
# EXPORTS
# ═══════════════════════════════════════════════════════════════

export -f search_omdb_movie get_omdb_metadata
export -f search_omdb_series search_omdb_episode get_omdb_series_metadata
export -f extract_omdb_plot extract_omdb_rating extract_omdb_poster extract_omdb_total_seasons
export -f extract_omdb_genre extract_omdb_runtime extract_omdb_year extract_omdb_rated
export -f fetch_omdb_description fetch_omdb_series_description omdb_configured
