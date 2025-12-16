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
    
    local refresh_flag=""
    [[ "$FORCE_REFRESH" == "true" ]] && refresh_flag="--refresh"
    
    # Use multi-source Python script (combines YTS + TPB)
    local script_path="${TERMFLIX_SCRIPTS_DIR:-$(dirname "$0")/../scripts}/fetch_multi_source_catalog.py"
    [[ ! -f "$script_path" ]] && script_path="$(dirname "${BASH_SOURCE[0]}")/../../scripts/fetch_multi_source_catalog.py"
    
    if [[ -f "$script_path" ]] && command -v python3 &>/dev/null; then
        python3 "$script_path" --limit "$limit" --page "$page" $refresh_flag 2>/dev/null
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
    
    local refresh_flag=""
    [[ "$FORCE_REFRESH" == "true" ]] && refresh_flag="--refresh"
    
    # Use multi-source Python script with download_count sort (trending)
    local script_path="${TERMFLIX_SCRIPTS_DIR:-$(dirname "$0")/../scripts}/fetch_multi_source_catalog.py"
    [[ ! -f "$script_path" ]] && script_path="$(dirname "${BASH_SOURCE[0]}")/../../scripts/fetch_multi_source_catalog.py"
    
    if [[ -f "$script_path" ]] && command -v python3 &>/dev/null; then
        python3 "$script_path" --limit "$limit" --page "$page" --sort download_count $refresh_flag 2>/dev/null
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
    
    local refresh_flag=""
    [[ "$FORCE_REFRESH" == "true" ]] && refresh_flag="--refresh"
    
    # Use multi-source Python script with rating sort (popular)
    local script_path="${TERMFLIX_SCRIPTS_DIR:-$(dirname "$0")/../scripts}/fetch_multi_source_catalog.py"
    [[ ! -f "$script_path" ]] && script_path="$(dirname "${BASH_SOURCE[0]}")/../../scripts/fetch_multi_source_catalog.py"
    
    if [[ -f "$script_path" ]] && command -v python3 &>/dev/null; then
        python3 "$script_path" --limit "$limit" --page "$page" --sort rating $refresh_flag 2>/dev/null
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
    local has_results=false
    
    local eztv_domains=("eztvx.to" "eztv.wf" "eztv.yt" "eztv1.xyz" "eztv.tf" "eztv.re")
    
    if command -v curl &> /dev/null && command -v jq &> /dev/null; then
        for domain in "${eztv_domains[@]}"; do
            local api_url="https://${domain}/api/get-torrents?limit=$limit&page=$page"
            local response=$(curl -s --max-time 5 "$api_url" 2>/dev/null)
            local count=$(echo "$response" | jq -r '.torrents_count // 0' 2>/dev/null)
            
            if [ "$count" -gt 0 ] 2>/dev/null; then
                echo "$response" | jq -r '.torrents[]? | select(.magnet_url != null and .magnet_url != "") | "EZTV|\(.title)|\(.magnet_url)|\(.seeds) seeds|\(.size_bytes / 1024 / 1024 | floor)MB|\(.date_released_unix // 0)"' 2>/dev/null
                has_results=true
                break
            fi
        done
    fi
    
    # Fallback to TPB HD TV Shows
    if [ "$has_results" = false ]; then
        local tpb_url="https://apibay.org/precompiled/data_top100_208.json"
        if command -v curl &> /dev/null && command -v jq &> /dev/null; then
            local tpb_response=$(curl -s --max-time 10 "$tpb_url" 2>/dev/null)
            if [ -n "$tpb_response" ]; then
                echo "$tpb_response" | jq -r '.[]? | select(.info_hash != null and .info_hash != "") | "TPB|\(.name)|magnet:?xt=urn:btih:\(.info_hash)|\(.seeders) seeds|\(.size / 1024 / 1024 | floor)MB|TV Show"' 2>/dev/null
            fi
        fi
    fi
}

# Get catalog by genre
get_catalog_by_genre() {
    local genre="$1"
    local limit="${2:-20}"
    
    local genre_id=""
    case "$(echo "$genre" | tr '[:upper:]' '[:lower:]')" in
        action) genre_id="Action" ;;
        adventure) genre_id="Adventure" ;;
        animation) genre_id="Animation" ;;
        comedy) genre_id="Comedy" ;;
        crime) genre_id="Crime" ;;
        documentary) genre_id="Documentary" ;;
        drama) genre_id="Drama" ;;
        family) genre_id="Family" ;;
        fantasy) genre_id="Fantasy" ;;
        horror) genre_id="Horror" ;;
        mystery) genre_id="Mystery" ;;
        romance) genre_id="Romance" ;;
        sci-fi|scifi|science-fiction) genre_id="Sci-Fi" ;;
        thriller) genre_id="Thriller" ;;
        war) genre_id="War" ;;
        western) genre_id="Western" ;;
        *) genre_id="$genre" ;;
    esac
    
    local base_url="https://yts.lt/api/v2/list_movies.json"
    local api_url="${base_url}?genre=${genre_id}&limit=${limit}&sort_by=date_added&order_by=desc"
    
    if command -v curl &> /dev/null && command -v jq &> /dev/null; then
        local response=$(curl -s --max-time 10 --retry 1 --retry-delay 2 \
            -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
            -H "Accept: application/json" \
            "$api_url" 2>/dev/null)
        
        if [ -n "$response" ]; then
            local status=$(echo "$response" | jq -r '.status // "fail"' 2>/dev/null)
            
            if [ "$status" = "ok" ]; then
                echo "$response" | jq -r '.data.movies[]? | select(.torrents != null and (.torrents | length) > 0) | .torrents[0] as $torrent | select($torrent.hash != null and $torrent.hash != "") | "YTS|\(.title) (\(.year))|magnet:?xt=urn:btih:\($torrent.hash)|\($torrent.quality // "N/A")|\($torrent.size // "N/A")|\(.genres | join(", "))|\(.medium_cover_image // "N/A")"' 2>/dev/null | head -20
            fi
        fi
    fi
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

# Export catalog fetching functions
export -f get_latest_movies get_trending_movies get_popular_movies get_latest_shows get_catalog_by_genre get_new_48h_movies
