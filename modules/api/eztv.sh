#!/usr/bin/env bash
#
# Termflix EZTV API Module
# Searches EZTV for TV show torrents with metadata enrichment
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_EZTV_LOADED:-}" ]] && return 0
_TERMFLIX_EZTV_LOADED=1

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

# Get script directory
EZTV_SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EZTV_BIN_DIR="${EZTV_SCRIPT_DIR}/../.."
EZTV_PYTHON_SCRIPT="${TERMFLIX_SCRIPTS_DIR:-${EZTV_BIN_DIR}/lib/termflix/scripts}/search_eztv.py"

# Source dependencies
if [[ -f "${EZTV_SCRIPT_DIR}/../core/config.sh" ]]; then
    source "${EZTV_SCRIPT_DIR}/../core/config.sh"
fi

if [[ -f "${EZTV_SCRIPT_DIR}/../core/colors.sh" ]]; then
    source "${EZTV_SCRIPT_DIR}/../core/colors.sh"
fi

# Cache settings
EZTV_CACHE_DIR="${HOME}/.cache/termflix/eztv"
EZTV_METADATA_CACHE_DIR="${HOME}/.cache/termflix/tv_metadata"
EZTV_CACHE_TTL=$((1 * 60 * 60))  # 1 hour in seconds

# ═══════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Generate cache key from string
_eztv_cache_key() {
    local input="$1"
    local normalized
    
    normalized=$(echo "$input" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
    
    if command -v md5 &>/dev/null; then
        echo -n "$normalized" | md5
    elif command -v md5sum &>/dev/null; then
        echo -n "$normalized" | md5sum | cut -d' ' -f1
    else
        python3 -c "import hashlib; print(hashlib.md5('${normalized}'.encode()).hexdigest())"
    fi
}

# Check if cache is valid
_eztv_cache_valid() {
    local cache_file="$1"
    local ttl="${2:-$EZTV_CACHE_TTL}"
    
    [[ ! -f "$cache_file" ]] && return 1
    
    local file_age=$(( $(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || stat -c%Y "$cache_file" 2>/dev/null) ))
    [[ $file_age -lt $ttl ]]
}

# Parse season/episode from title (bash helper)
parse_season_episode() {
    local title="$1"
    
    # Try S01E05 format
    if [[ "$title" =~ [Ss]([0-9]{1,2})[Ee]([0-9]{1,3}) ]]; then
        echo "season=${BASH_REMATCH[1]} episode=${BASH_REMATCH[2]}"
        return 0
    fi
    
    # Try 1x05 format
    if [[ "$title" =~ ([0-9]{1,2})[xX]([0-9]{1,3}) ]]; then
        echo "season=${BASH_REMATCH[1]} episode=${BASH_REMATCH[2]}"
        return 0
    fi
    
    echo "season=0 episode=0"
    return 1
}

# Format episode label for display
format_episode_label() {
    local season="${1:-0}"
    local episode="${2:-0}"
    
    if [[ $season -gt 0 && $episode -gt 0 ]]; then
        printf "S%02dE%02d" "$season" "$episode"
    elif [[ $season -gt 0 ]]; then
        printf "S%02d" "$season"
    else
        echo ""
    fi
}

# ═══════════════════════════════════════════════════════════════
# SEARCH FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Search EZTV for TV show torrents
# Usage: search_eztv_show "show name"
# Output: Array of pipe-delimited results
search_eztv_show() {
    local query="$1"
    
    if [[ -z "$query" ]]; then
        return 1
    fi
    
    # Check if Python script exists
    if [[ ! -f "$EZTV_PYTHON_SCRIPT" ]]; then
        echo "Error: EZTV search script not found at $EZTV_PYTHON_SCRIPT" >&2
        return 1
    fi
    
    # Run Python search script
    SEARCH_QUERY="$query" python3 "$EZTV_PYTHON_SCRIPT" 2>/dev/null
}

# Search and return results as bash array
# Usage: mapfile -t results < <(search_eztv_array "show name")
search_eztv_array() {
    local query="$1"
    search_eztv_show "$query"
}

# Get best torrent for a show (highest seeds)
get_best_eztv_torrent() {
    local query="$1"
    local results
    
    results=$(search_eztv_show "$query" | head -1)
    
    if [[ -n "$results" ]]; then
        echo "$results"
        return 0
    fi
    
    return 1
}

# ═══════════════════════════════════════════════════════════════
# METADATA FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Get TV show metadata using IMDB ID
# Uses TMDB's /find endpoint with IMDB ID
get_tv_show_info() {
    local identifier="$1"  # Can be show name or IMDB ID
    local tmdb_api_key="${TMDB_API_KEY:-}"
    
    # Check for TMDB API key
    if [[ -z "$tmdb_api_key" ]]; then
        # Try to get from config
        if command -v get_tmdb_api_key &>/dev/null; then
            tmdb_api_key=$(get_tmdb_api_key)
        fi
    fi
    
    if [[ -z "$tmdb_api_key" ]]; then
        echo '{"error": "No TMDB API key configured"}'
        return 1
    fi
    
    # Create cache directory
    mkdir -p "$EZTV_METADATA_CACHE_DIR"
    
    # Check cache
    local cache_key=$(_eztv_cache_key "$identifier")
    local cache_file="${EZTV_METADATA_CACHE_DIR}/${cache_key}.json"
    
    if _eztv_cache_valid "$cache_file" $((7 * 24 * 60 * 60)); then
        cat "$cache_file"
        return 0
    fi
    
    local response=""
    
    # If it's an IMDB ID, use /find endpoint
    if [[ "$identifier" =~ ^tt[0-9]+ ]]; then
        response=$(curl -sL --max-time 5 \
            "https://api.themoviedb.org/3/find/${identifier}?api_key=${tmdb_api_key}&external_source=imdb_id" \
            2>/dev/null)
        
        # Extract TV result
        response=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tv_results = data.get('tv_results', [])
    if tv_results:
        r = tv_results[0]
        print(json.dumps({
            'id': r.get('id'),
            'name': r.get('name'),
            'overview': r.get('overview', ''),
            'first_air_date': r.get('first_air_date', ''),
            'vote_average': r.get('vote_average', 0),
            'poster_path': r.get('poster_path', '')
        }))
    else:
        print(json.dumps({'error': 'No TV show found'}))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null)
    else
        # Search by name
        local encoded_name
        encoded_name=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$identifier'))")
        
        response=$(curl -sL --max-time 5 \
            "https://api.themoviedb.org/3/search/tv?api_key=${tmdb_api_key}&query=${encoded_name}" \
            2>/dev/null)
        
        # Extract first result
        response=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    if results:
        r = results[0]
        print(json.dumps({
            'id': r.get('id'),
            'name': r.get('name'),
            'overview': r.get('overview', ''),
            'first_air_date': r.get('first_air_date', ''),
            'vote_average': r.get('vote_average', 0),
            'poster_path': r.get('poster_path', '')
        }))
    else:
        print(json.dumps({'error': 'No TV show found'}))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null)
    fi
    
    # Cache and return
    if [[ -n "$response" ]]; then
        echo "$response" > "$cache_file"
        echo "$response"
        return 0
    fi
    
    echo '{"error": "Failed to fetch TV show info"}'
    return 1
}

# Get TV show poster URL
get_tv_show_poster() {
    local identifier="$1"
    local size="${2:-w500}"  # w92, w154, w185, w342, w500, w780, original
    
    local metadata
    metadata=$(get_tv_show_info "$identifier")
    
    local poster_path
    poster_path=$(echo "$metadata" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('poster_path', ''))
except:
    print('')
" 2>/dev/null)
    
    if [[ -n "$poster_path" && "$poster_path" != "null" ]]; then
        echo "https://image.tmdb.org/t/p/${size}${poster_path}"
        return 0
    fi
    
    return 1
}

# Get TV show description
get_tv_show_description() {
    local identifier="$1"
    
    local metadata
    metadata=$(get_tv_show_info "$identifier")
    
    echo "$metadata" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('overview', 'No description available.'))
except:
    print('No description available.')
" 2>/dev/null
}

# Get TV show rating
get_tv_show_rating() {
    local identifier="$1"
    
    local metadata
    metadata=$(get_tv_show_info "$identifier")
    
    echo "$metadata" | python3 -c "
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
" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Parse EZTV result line into variables
# Usage: parse_eztv_result "$line" && echo "$EZTV_TITLE"
parse_eztv_result() {
    local line="$1"
    
    IFS='|' read -r EZTV_SOURCE EZTV_TITLE EZTV_MAGNET EZTV_QUALITY EZTV_SEEDS EZTV_SIZE EZTV_SEASON EZTV_EPISODE EZTV_IMDB_ID <<< "$line"
    
    # Export for use in calling context
    export EZTV_SOURCE EZTV_TITLE EZTV_MAGNET EZTV_QUALITY EZTV_SEEDS EZTV_SIZE EZTV_SEASON EZTV_EPISODE EZTV_IMDB_ID
}

# Check if EZTV module is ready
eztv_configured() {
    [[ -f "$EZTV_PYTHON_SCRIPT" ]] && command -v python3 &>/dev/null
}

# ═══════════════════════════════════════════════════════════════
# EXPORTS
# ═══════════════════════════════════════════════════════════════

export -f search_eztv_show search_eztv_array get_best_eztv_torrent
export -f get_tv_show_info get_tv_show_poster get_tv_show_description get_tv_show_rating
export -f parse_season_episode format_episode_label parse_eztv_result
export -f eztv_configured
