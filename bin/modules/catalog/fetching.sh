#!/usr/bin/env bash
#
# Termflix Catalog Fetching Module
# Functions for fetching movie/show data from various sources
#

# Get latest movies - Multi-source (YTS + TPB)
# Uses Python script to aggregate torrents from multiple sources
get_latest_movies() {
    local limit="${1:-50}"
    local page="${2:-1}"
    
    # Check if Python catalog backend is enabled
    if command -v use_python_catalog &>/dev/null && use_python_catalog; then
        local catalog_script="${TERMFLIX_LIB_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../lib/termflix}/scripts/catalog.py"
        
        if [[ -f "$catalog_script" ]] && command -v python3 &>/dev/null; then
            python3 "$catalog_script" latest "$limit" "$page" 2>/dev/null && return 0
        fi
        # Fallback to legacy if Python script not found
    fi
    
    # Legacy implementation: fetch_multi_source_catalog.py
    local extra_args=""
    [[ "$FORCE_REFRESH" == "true" ]] && extra_args+=" --refresh"
    [[ -n "$CURRENT_QUERY" ]] && extra_args+=" --query \"$CURRENT_QUERY\""
    [[ -n "$CURRENT_GENRE" ]] && extra_args+=" --genre \"$CURRENT_GENRE\""
    [[ -n "$CURRENT_MIN_RATING" ]] && extra_args+=" --min-rating $CURRENT_MIN_RATING"
    [[ -n "$CURRENT_SORT" ]] && extra_args+=" --sort $CURRENT_SORT"
    [[ -n "$CURRENT_ORDER" ]] && extra_args+=" --order-by $CURRENT_ORDER"
    [[ -n "$CURRENT_CATEGORY" ]] && extra_args+=" --category $CURRENT_CATEGORY"
    
    # Use multi-source Python script (combines YTS + TPB)
    local script_path="${TERMFLIX_SCRIPTS_DIR:-$(dirname "$0")/../scripts}/fetch_multi_source_catalog.py"
    [[ ! -f "$script_path" ]] && script_path="$(dirname "${BASH_SOURCE[0]}")/../../scripts/fetch_multi_source_catalog.py"
    
    if [[ -f "$script_path" ]] && command -v python3 &>/dev/null; then
        python3 "$script_path" --limit "$limit" --page "$page" --category movies $extra_args 2>/dev/null
        local ret=$?
        [[ $ret -eq 0 ]] && return 0
    fi
    
    # Fallback: YTS only (if Python script not available)
    local yts_domains=("yts.lt" "yts.do" "yts.mx")
    
    if command -v curl &> /dev/null && command -v jq &> /dev/null; then
        for domain in "${yts_domains[@]}"; do
            local api_url="https://${domain}/api/v2/list_movies.json?limit=${limit}&sort_by=date_added&order_by=desc&page=${page}"
            local response=$(curl -s --max-time 5 --connect-timeout 3 \
                -H "User-Agent: Mozilla/5.0" \
                "$api_url" 2>/dev/null)
            
            if [ -n "$response" ]; then
                local status=$(echo "$response" | jq -r '.status // "fail"' 2>/dev/null)
                
                if [ "$status" = "ok" ]; then
                    echo "$response" | jq -r '.data.movies[]? | 
                        select(.torrents != null and (.torrents | length) > 0) | 
                        .torrents[0] as $torrent | 
                        select($torrent.hash != null and $torrent.hash != "") | 
                        "YTS|\(.title) (\(.year))|magnet:?xt=urn:btih:\($torrent.hash)|\($torrent.quality // "N/A")|\($torrent.size // "N/A")|\($torrent.seeds // 0)|\(.medium_cover_image // "N/A")"' 2>/dev/null
                    return 0
                fi
            fi
        done
    fi
}

# Get trending movies - Multi-source (YTS + TPB)
# Uses Python script with download_count sort
get_trending_movies() {
    local limit="${1:-50}"
    local page="${2:-1}"
    
    # Check if Python catalog backend is enabled
    if command -v use_python_catalog &>/dev/null && use_python_catalog; then
        local catalog_script="${TERMFLIX_LIB_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../lib/termflix}/scripts/catalog.py"
        
        if [[ -f "$catalog_script" ]] && command -v python3 &>/dev/null; then
            python3 "$catalog_script" trending "$limit" "$page" 2>/dev/null && return 0
        fi
    fi
    
    # Legacy implementation
    local extra_args=""
    [[ "$FORCE_REFRESH" == "true" ]] && extra_args+=" --refresh"
    [[ -n "$CURRENT_QUERY" ]] && extra_args+=" --query \"$CURRENT_QUERY\""
    [[ -n "$CURRENT_GENRE" ]] && extra_args+=" --genre \"$CURRENT_GENRE\""
    [[ -n "$CURRENT_MIN_RATING" ]] && extra_args+=" --min-rating $CURRENT_MIN_RATING"
    [[ -n "$CURRENT_CATEGORY" ]] && extra_args+=" --category $CURRENT_CATEGORY"
    
    # Use multi-source Python script with download_count sort (trending)
    local script_path="${TERMFLIX_SCRIPTS_DIR:-$(dirname "$0")/../scripts}/fetch_multi_source_catalog.py"
    [[ ! -f "$script_path" ]] && script_path="$(dirname "${BASH_SOURCE[0]}")/../../scripts/fetch_multi_source_catalog.py"
    
    if [[ -f "$script_path" ]] && command -v python3 &>/dev/null; then
        python3 "$script_path" --limit "$limit" --page "$page" --sort download_count --category movies $extra_args 2>/dev/null
        local ret=$?
        [[ $ret -eq 0 ]] && return 0
    fi
    
    # Fallback: YTS only
    local base_url="https://yts.lt/api/v2/list_movies.json"
    local api_url="${base_url}?limit=${limit}&sort_by=download_count&order_by=desc&page=${page}"
    
    if command -v curl &> /dev/null && command -v jq &> /dev/null; then
        local response=$(curl -s --max-time 5 "$api_url" 2>/dev/null)
        
        if [ -n "$response" ]; then
            local status=$(echo "$response" | jq -r '.status // "fail"' 2>/dev/null)
            
            if [ "$status" = "ok" ]; then
                echo "$response" | jq -r '.data.movies[]? | 
                    select(.torrents != null and (.torrents | length) > 0) | 
                    .torrents[0] as $torrent | 
                    select($torrent.hash != null and $torrent.hash != "") | 
                    "YTS|\(.title) (\(.year))|magnet:?xt=urn:btih:\($torrent.hash)|\($torrent.quality // "N/A")|\($torrent.size // "N/A")|\($torrent.seeds // 0)|\(.medium_cover_image // "N/A")"' 2>/dev/null
                return 0
            fi
        fi
    fi
}

# Get popular movies - Multi-source (YTS + TPB)
# Get popular movies - Multi-source (YTS + TPB)
get_popular_movies() {
    local limit="${1:-50}"
    local page="${2:-1}"
    
    # Check if Python catalog backend is enabled
    if command -v use_python_catalog &>/dev/null && use_python_catalog; then
        local catalog_script="${TERMFLIX_LIB_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../lib/termflix}/scripts/catalog.py"
        
        if [[ -f "$catalog_script" ]] && command -v python3 &>/dev/null; then
            python3 "$catalog_script" popular "$limit" "$page" 2>/dev/null && return 0
        fi
    fi
    
    # Legacy implementation
    local extra_args=""
    [[ "$FORCE_REFRESH" == "true" ]] && extra_args+=" --refresh"
    [[ -n "$CURRENT_QUERY" ]] && extra_args+=" --query \"$CURRENT_QUERY\""
    [[ -n "$CURRENT_GENRE" ]] && extra_args+=" --genre \"$CURRENT_GENRE\""
    [[ -n "$CURRENT_MIN_RATING" ]] && extra_args+=" --min-rating $CURRENT_MIN_RATING"
    [[ -n "$CURRENT_CATEGORY" ]] && extra_args+=" --category $CURRENT_CATEGORY"
    
    # Use multi-source Python script with rating sort (popular)
    local script_path="${TERMFLIX_SCRIPTS_DIR:-$(dirname "$0")/../scripts}/fetch_multi_source_catalog.py"
    [[ ! -f "$script_path" ]] && script_path="$(dirname "${BASH_SOURCE[0]}")/../../scripts/fetch_multi_source_catalog.py"
    
    if [[ -f "$script_path" ]] && command -v python3 &>/dev/null; then
        python3 "$script_path" --limit "$limit" --page "$page" --sort rating --category movies $extra_args 2>/dev/null
        local ret=$?
        [[ $ret -eq 0 ]] && return 0
    fi

    # Fallback to direct API call if python fails
    local base_url="https://yts.lt/api/v2/list_movies.json"
    local api_url="${base_url}?limit=${limit}&sort_by=rating&order_by=desc&minimum_rating=7&page=${page}"
    
    if command -v curl &> /dev/null && command -v jq &> /dev/null; then
        local response=$(curl -s --max-time 3 --connect-timeout 2 \
            -H "User-Agent: Mozilla" \
            "$api_url" 2>/dev/null)
        
        if [ -n "$response" ] && [ "$response" != "" ]; then
            local status=$(echo "$response" | jq -r '.status // "fail"' 2>/dev/null)
            
            if [ "$status" = "ok" ]; then
                # Simplistic fallback format (not COMBINED)
                 echo "$response" | jq -r '.data.movies[]? | select(.torrents != null) | "YTS|\(.title) (\(.year))|magnet:?xt=urn:btih:\(.torrents[0].hash)|\(.torrents[0].quality)|\(.torrents[0].size)|\(.torrents[0].seeds)|\(.medium_cover_image)"' 2>/dev/null
                return 0
            fi
        fi
    fi
    
    # Fallback to TPB popular
    echo -e "${YELLOW}[TPB]${RESET} YTS unavailable, using ThePirateBay popular..." >&2
    local tpb_url="https://apibay.org/precompiled/data_top100_205.json"
    if command -v curl &> /dev/null && command -v jq &> /dev/null; then
        local tpb_response=$(curl -s --max-time 5 "$tpb_url" 2>/dev/null)
        if [ -n "$tpb_response" ]; then
            echo "$tpb_response" | jq -r '.[]? | select(.info_hash != null and .info_hash != "") | "TPB|\(.name)|magnet:?xt=urn:btih:\(.info_hash)|\(.seeders) seeds|\(.size / 1024 / 1024 | floor)MB|Popular"' 2>/dev/null
        fi
    fi
}

# Get latest TV shows from EZTV (with domain rotation + TPB fallback)
get_latest_shows() {
    local limit="${1:-50}"
    local page="${2:-1}"
    
    # Check if Python catalog backend is enabled
    if command -v use_python_catalog &>/dev/null && use_python_catalog; then
        local catalog_script="${TERMFLIX_LIB_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../lib/termflix}/scripts/catalog.py"
        
        if [[ -f "$catalog_script" ]] && command -v python3 &>/dev/null; then
            python3 "$catalog_script" shows "$limit" "$page" 2>/dev/null && return 0
        fi
    fi
    
    # Use multi-source Python script (now handles grouping)
    local extra_args=""
    [[ "$FORCE_REFRESH" == "true" ]] && extra_args+=" --refresh"
    [[ -n "$CURRENT_QUERY" ]] && extra_args+=" --query \"$CURRENT_QUERY\""
    [[ -n "$CURRENT_GENRE" ]] && extra_args+=" --genre \"$CURRENT_GENRE\""
    [[ -n "$CURRENT_MIN_RATING" ]] && extra_args+=" --min-rating $CURRENT_MIN_RATING"
    [[ -n "$CURRENT_SORT" ]] && extra_args+=" --sort $CURRENT_SORT"
    [[ -n "$CURRENT_ORDER" ]] && extra_args+=" --order-by $CURRENT_ORDER"
    
    local script_path="${TERMFLIX_SCRIPTS_DIR:-$(dirname "$0")/../scripts}/fetch_multi_source_catalog.py"
    [[ ! -f "$script_path" ]] && script_path="$(dirname "${BASH_SOURCE[0]}")/../../scripts/fetch_multi_source_catalog.py"
    
    if [[ -f "$script_path" ]] && command -v python3 &>/dev/null; then
        python3 "$script_path" --limit "$limit" --page "$page" --category shows $extra_args 2>/dev/null
        return $?
    fi
    
    # No fallback - prefer showing "no results" over broken ungrouped data
    return 1
}

# Get catalog by genre
# Get catalog by genre (Unified)
get_catalog_by_genre() {
    # If using globals, arg1 might be empty or redundant
    local genre_arg="${1:-$CURRENT_GENRE}"
    local limit="${2:-50}" 
    local page="${3:-1}"
    
    # If no genre provided, fall back to Action
    [[ -z "$genre_arg" ]] && genre_arg="Action"
    
    # Check if Python catalog backend is enabled
    if command -v use_python_catalog &>/dev/null && use_python_catalog; then
        local catalog_script="${TERMFLIX_LIB_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../lib/termflix}/scripts/catalog.py"
        
        if [[ -f "$catalog_script" ]] && command -v python3 &>/dev/null; then
            python3 "$catalog_script" genre "$genre_arg" "$limit" 2>/dev/null && return 0
        fi
    fi
    
    # Legacy implementation
    local extra_args=""
    [[ "$FORCE_REFRESH" == "true" ]] && extra_args+=" --refresh"
    # Ensure genre arg is passed
    extra_args+=" --genre \"$genre_arg\""
    
    [[ -n "$CURRENT_QUERY" ]] && extra_args+=" --query \"$CURRENT_QUERY\""
    [[ -n "$CURRENT_MIN_RATING" ]] && extra_args+=" --min-rating $CURRENT_MIN_RATING"
    [[ -n "$CURRENT_SORT" ]] && extra_args+=" --sort $CURRENT_SORT"
    [[ -n "$CURRENT_ORDER" ]] && extra_args+=" --order $CURRENT_ORDER"

    # Use multi-source Python script
    local script_path="${TERMFLIX_SCRIPTS_DIR:-$(dirname "$0")/../scripts}/fetch_multi_source_catalog.py"
    [[ ! -f "$script_path" ]] && script_path="$(dirname "${BASH_SOURCE[0]}")/../../scripts/fetch_multi_source_catalog.py"
    
    if [[ -f "$script_path" ]] && command -v python3 &>/dev/null; then
        python3 "$script_path" --limit "$limit" --page "$page" $extra_args 2>/dev/null
        return $?
    fi
    
    # Legacy fallback logic removed for cleaner integration
    return 1
}

# Get new movies from last 48 hours (TPB 48h precompiled)
get_new_48h_movies() {
    local limit="${1:-100}"
    local page="${2:-1}"
    
    local tpb_url="https://apibay.org/precompiled/data_top100_48h.json"
    
    if command -v curl &> /dev/null && command -v jq &> /dev/null; then
        curl -s --max-time 10 "$tpb_url" 2>/dev/null | jq -r '
            .[]? | 
            select(.info_hash != null and .info_hash != "") | 
            "TPB|\(.name)|magnet:?xt=urn:btih:\(.info_hash)|\(.seeders) seeds|\((.size / 1024 / 1024 | floor))MB|\(.imdb // "N/A")"
        ' 2>/dev/null | head -n "$limit"
    fi
}

# Get combined Latest Movies + Shows (for "All" category)
get_latest_all() {
    local limit="${1:-50}"
    local page="${2:-1}"
    
    # Fetch movies and shows in parallel (using subshells)
    local tmp_movies=$(mktemp)
    local tmp_shows=$(mktemp)
    
    # Parallel fetch
    (get_latest_movies "$((limit/2))" "$page" > "$tmp_movies" 2>/dev/null) &
    local pid_movies=$!
    (get_latest_shows "$((limit/2))" "$page" > "$tmp_shows" 2>/dev/null) &
    local pid_shows=$!
    
    # Wait for both
    wait $pid_movies 2>/dev/null
    wait $pid_shows 2>/dev/null
    
    # Interleave results (movie, show, movie, show...)
    local movies=()
    local shows=()
    
    while IFS= read -r line; do
        [[ -n "$line" ]] && movies+=("$line")
    done < "$tmp_movies"
    
    while IFS= read -r line; do
        [[ -n "$line" ]] && shows+=("$line")
    done < "$tmp_shows"
    
    rm -f "$tmp_movies" "$tmp_shows" 2>/dev/null
    
    # Interleave: alternating movies and shows
    local max=${#movies[@]}
    [[ ${#shows[@]} -gt $max ]] && max=${#shows[@]}
    
    for ((i=0; i<max; i++)); do
        [[ -n "${movies[$i]}" ]] && echo "${movies[$i]}"
        [[ -n "${shows[$i]}" ]] && echo "${shows[$i]}"
    done
}

# Export catalog fetching functions
export -f get_latest_movies get_trending_movies get_popular_movies get_latest_shows get_catalog_by_genre get_new_48h_movies get_latest_all

