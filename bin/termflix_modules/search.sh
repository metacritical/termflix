#!/usr/bin/env bash
#
# Termflix Search Module
# Search wrappers to Python scripts and result grouping
#

# Search YTS via Python script
search_yts() {
    local query="$1"
    
    echo -e "${MAGENTA}[${PINK}YTS${MAGENTA}]${RESET} Searching..." >&2
    
    if ! command -v python3 &> /dev/null; then
        return 1
    fi
    
    export YTS_QUERY="$query"
    python3 "$TERMFLIX_SCRIPTS_DIR/search_yts.py" 2>/tmp/termflix_last_error.log
}

# Search 1337x via Python script
search_1337x() {
    local query="$1"
    
    echo -e "${MAGENTA}[${PINK}1337x${MAGENTA}]${RESET} Searching..." >&2
    
    if ! command -v python3 &> /dev/null; then
        return 1
    fi
    
    export SEARCH_QUERY="$query"
    python3 "$TERMFLIX_SCRIPTS_DIR/search_1337x.py" 2>/tmp/termflix_last_error.log
}

# Search ThePirateBay via Python script
search_tpb() {
    local query="$1"
    
    echo -e "${MAGENTA}[${PINK}ThePirateBay${MAGENTA}]${RESET} Searching..." >&2
    
    if ! command -v python3 &> /dev/null; then
        return 1
    fi
    
    export SEARCH_QUERY="$query"
    python3 "$TERMFLIX_SCRIPTS_DIR/search_tpb.py" 2>/tmp/termflix_last_error.log
}

# Search EZTV via Python script
search_eztv() {
    local query="$1"
    
    echo -e "${MAGENTA}[${PINK}EZTV${MAGENTA}]${RESET} Searching TV shows..." >&2
    
    if ! command -v python3 &> /dev/null; then
        return 1
    fi
    
    export SEARCH_QUERY="$query"
    python3 "$TERMFLIX_SCRIPTS_DIR/search_eztv.py" 2>/tmp/termflix_last_error.log
}

# Group results by title and year (wrapper to Python script)
group_results() {
    if ! command -v python3 &> /dev/null; then
        cat  # Pass through if Python not available
        return 0
    fi
    
    python3 "$TERMFLIX_SCRIPTS_DIR/group_results.py" 2>/tmp/termflix_last_error.log
}

# Get YTS catalog movies via Python script
get_ytsrs_movies() {
    local genre="${1:-}"
    local quality="${2:-1080p}"
    local sort="${3:-seeds}"
    local limit="${4:-20}"
    local page="${5:-1}"

    if ! command -v python3 &> /dev/null; then
        return 1
    fi
    
    python3 "$TERMFLIX_SCRIPTS_DIR/get_ytsrs_movies.py" "$sort" "$limit" "$page" "$genre"
    return 0
}

# Helper function to get source name from function name
get_source_name() {
    local func_name="$1"
    case "$func_name" in
        get_latest_movies|get_trending_movies|get_popular_movies|get_catalog_by_genre)
            echo "YTS"
            ;;
        get_latest_shows)
            echo "EZTV"
            ;;
        search_ytsrs|get_ytsrs_movies)
            echo "YTS"
            ;;
        search_tpb)
            echo "TPB"
            ;;
        search_eztv)
            echo "EZTV"
            ;;
        search_1337x)
            echo "1337x"
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

# Search all sources in parallel
search_all() {
    local query="$1"
    local temp_results="/tmp/termflix_search_$$"
    
    # Search all sources in parallel
    {
        search_yts "$query" 2>/dev/null
        search_tpb "$query" 2>/dev/null
        search_1337x "$query" 2>/dev/null
        search_eztv "$query" 2>/dev/null
    } > "$temp_results"
    
    # Group and output results
    if [ -s "$temp_results" ]; then
        cat "$temp_results" | group_results
        rm -f "$temp_results"
        return 0
    fi
    
    rm -f "$temp_results"
    return 1
}
