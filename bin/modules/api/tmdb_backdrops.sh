#!/usr/bin/env bash
#
# Termflix TMDB Backdrop Fetching Module
# Fetches high-quality backdrop images for pre-buffering splash screen
#

[[ -n "${_TERMFLIX_TMDB_BACKDROPS_LOADED:-}" ]] && return 0
_TERMFLIX_TMDB_BACKDROPS_LOADED=1

# Source dependencies
BACKDROP_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${BACKDROP_MODULE_DIR}/tmdb.sh" ]] && source "${BACKDROP_MODULE_DIR}/tmdb.sh"

# Configuration
BACKDROP_CACHE_DIR="${HOME}/.cache/termflix/tmdb/backdrops"
BACKDROP_CACHE_TTL=$((30 * 24 * 60 * 60))  # 30 days (backdrops don't change often)
mkdir -p "$BACKDROP_CACHE_DIR"

# Get backdrop image for a movie by IMDB ID
# Args: $1 = IMDB ID (e.g. tt1234567)
# Returns: Path to downloaded backdrop image, or empty string if not found
get_tmdb_backdrop() {
    local imdb_id="$1"
    
    # Validate IMDB ID
    if [[ ! "$imdb_id" =~ ^tt[0-9]+$ ]]; then
        echo "" >&2
        return 1
    fi
    
    # Check cache first
    local cache_file="${BACKDROP_CACHE_DIR}/${imdb_id}.jpg"
    if [[ -f "$cache_file" ]]; then
        local file_age=$(( $(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || echo 0) ))
        if [[ $file_age -lt $BACKDROP_CACHE_TTL ]]; then
            echo "$cache_file"
            return 0
        fi
    fi
    
    # Fetch from TMDB API
    if [[ -z "${TMDB_API_KEY:-}" ]]; then
        # Try to source TMDB module if not already loaded
        [[ -f "${BACKDROP_MODULE_DIR}/tmdb.sh" ]] && source "${BACKDROP_MODULE_DIR}/tmdb.sh"
        TMDB_API_KEY="${TMDB_API_KEY:-$(get_tmdb_api_key 2>/dev/null)}"
    fi
    
    if [[ -z "$TMDB_API_KEY" ]]; then
        echo "" >&2
        return 1
    fi
    
    # Step 1: Find TMDB movie ID using IMDB ID
    local find_url="https://api.themoviedb.org/3/find/${imdb_id}?api_key=${TMDB_API_KEY}&external_source=imdb_id"
    local find_response=$(curl -sL "$find_url" 2>/dev/null)
    
    if [[ -z "$find_response" ]]; then
        echo "" >&2
        return 1
    fi
    
    # Extract TMDB movie ID
    local tmdb_id=$(echo "$find_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('movie_results', [])
    if results:
        print(results[0]['id'])
except:
    pass
" 2>/dev/null)
    
    if [[ -z "$tmdb_id" ]]; then
        echo "" >&2
        return 1
    fi
    
    # Step 2: Fetch images for this movie
    local images_url="https://api.themoviedb.org/3/movie/${tmdb_id}/images?api_key=${TMDB_API_KEY}"
    local images_response=$(curl -sL "$images_url" 2>/dev/null)
    
    if [[ -z "$images_response" ]]; then
        echo "" >&2
        return 1
    fi
    
    # Extract best backdrop (highest resolution, prefer 1920x1080)
    local backdrop_path=$(echo "$images_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    backdrops = data.get('backdrops', [])
    if not backdrops:
        sys.exit(1)
    
    # Sort by resolution (prefer 1920x1080, then highest)
    def score(b):
        w, h = b.get('width', 0), b.get('height', 0)
        if w == 1920 and h == 1080:
            return 10000  # Perfect match
        return w * h  # Otherwise prefer highest resolution
    
    best = sorted(backdrops, key=score, reverse=True)[0]
    print(best['file_path'])
except:
    sys.exit(1)
" 2>/dev/null)
    
    if [[ -z "$backdrop_path" ]]; then
        echo "" >&2
        return 1
    fi
    
    # Step 3: Download backdrop image
    local backdrop_url="https://image.tmdb.org/t/p/original${backdrop_path}"
    if curl -sL "$backdrop_url" -o "$cache_file" 2>/dev/null; then
        # Verify it's a valid image
        if file "$cache_file" 2>/dev/null | grep -qi "image"; then
            echo "$cache_file"
            return 0
        else
            rm -f "$cache_file"
        fi
    fi
    
    echo "" >&2
    return 1
}

# Export functions
export -f get_tmdb_backdrop
