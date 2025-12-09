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
            echo "TPB"  # Now using TPB as primary source
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

# ============================================================
# UNIFIED SEARCH LOGIC
# ============================================================

# Unified search using Stremio-style APIs
search_torrent() {
    local query="$1"
    local all_results=()
    
    echo -e "${BOLD}${YELLOW}Searching for:${RESET} ${BOLD}$query${RESET}"
    echo
    
    # Search all sources (similar to how Stremio aggregates)
    # Collect results into array using process substitution
    {
        search_yts "$query" 2>/dev/null
        search_tpb "$query" 2>/dev/null
        search_eztv "$query" 2>/dev/null
        search_1337x "$query" 2>/dev/null
    } | while IFS= read -r line || [ -n "$line" ]; do
        if [ -n "$line" ] && [[ "$line" =~ \| ]]; then
            all_results+=("$line")
        fi
    done
    
    # Note: Due to pipe creating subshell, we need to use a different approach
    # Let's use a temp file instead and run searches in parallel with timeouts
    local temp_file=$(mktemp 2>/dev/null || echo "/tmp/torrent_$$")
    local search_pids=()
    
    # Run all searches in parallel (each has its own timeout via curl --max-time)
    (search_yts "$query" 2>/dev/null || true) >> "$temp_file" &
    search_pids+=($!)
    (search_ytsrs "$query" 2>/dev/null || true) >> "$temp_file" &
    search_pids+=($!)
    (search_tpb "$query" 2>/dev/null || true) >> "$temp_file" &
    search_pids+=($!)
    (search_eztv "$query" 2>/dev/null || true) >> "$temp_file" &
    search_pids+=($!)
    (search_1337x "$query" 2>/dev/null || true) >> "$temp_file" &
    search_pids+=($!)
    
    # Wait for all searches to complete (max 10 seconds total)
    local wait_count=0
    while [ $wait_count -lt 20 ]; do
        local all_done=true
        for pid in "${search_pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                all_done=false
                break
            fi
        done
        if [ "$all_done" = true ]; then
            break
        fi
        sleep 0.5
        wait_count=$((wait_count + 1))
    done
    
    # Kill any remaining processes after timeout
    for pid in "${search_pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    wait "${search_pids[@]}" 2>/dev/null || true
    
    # Read results from temp file
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip empty lines and lines without pipe separator
            if [ -n "$line" ] && echo "$line" | grep -q '|'; then
                # Remove any trailing whitespace
                line=$(echo "$line" | sed 's/[[:space:]]*$//')
                all_results+=("$line")
            fi
        done < "$temp_file"
    fi
    
    rm -f "$temp_file" 2>/dev/null
    
    rm -f "$temp_file" 2>/dev/null
    
    # Group results
    local grouped_results=()
    if [ ${#all_results[@]} -gt 0 ]; then
        local group_input=$(mktemp)
        printf "%s\n" "${all_results[@]}" > "$group_input"
        local group_output=$(cat "$group_input" | group_results)
        if [ -n "$group_output" ]; then
             while IFS= read -r line || [ -n "$line" ]; do
                 grouped_results+=("$line")
             done <<< "$group_output"
             all_results=("${grouped_results[@]}")
        fi
        rm -f "$group_input"
    fi
    
    # Remove duplicates (fallback)
    if [ ${#all_results[@]} -gt 0 ]; then
        local unique_results=()
        local seen_hashes=()
        for result in "${all_results[@]}"; do
            IFS='|' read -r source name magnet quality size extra <<< "$result"
            # Extract hash from magnet link
            local hash=$(echo "$magnet" | grep -oE 'btih:[a-fA-F0-9]+' | cut -d: -f2 | tr '[:upper:]' '[:lower:]')
            if [ -n "$hash" ]; then
                # Check if we've seen this hash before
                local seen=false
                for seen_hash in "${seen_hashes[@]}"; do
                    if [ "$hash" = "$seen_hash" ]; then
                        seen=true
                        break
                    fi
                done
                if [ "$seen" = false ]; then
                    unique_results+=("$result")
                    seen_hashes+=("$hash")
                fi
            else
                # If no hash, just add it (shouldn't happen but be safe)
                unique_results+=("$result")
            fi
        done
        all_results=("${unique_results[@]}")
    fi
    
    if [ ${#all_results[@]} -eq 0 ]; then
        echo -e "${RED}No results found${RESET}"
        echo
        echo "Try:"
        echo "  - Check your internet connection"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "  - Install jq: ${CYAN}brew install jq${RESET}"
            echo "  - Install python3: ${CYAN}brew install python3${RESET} (for YTSRS search)"
        else
            echo "  - Install jq: ${CYAN}sudo apt-get install jq${RESET} (Debian/Ubuntu) or ${CYAN}sudo yum install jq${RESET} (RHEL/CentOS)"
            echo "  - Install python3: ${CYAN}sudo apt-get install python3${RESET} (Debian/Ubuntu) or ${CYAN}sudo yum install python3${RESET} (RHEL/CentOS)"
        fi
        echo "  - Try a different search query"
        echo "  - The search APIs may be temporarily unavailable"
        return 1
    fi
    
    # Display results using FZF
    local selection_line
    if selection_line=$(show_fzf_catalog "Search Results for: $query" all_results); then
         handle_fzf_selection "$selection_line"
    fi
}
