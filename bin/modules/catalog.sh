#!/usr/bin/env bash
#
# Termflix Catalog Module
# Grid rendering, catalog display, and browsing functions
#

# Source catalog fetching functions
source "$(dirname "${BASH_SOURCE[0]}")/catalog/fetching.sh"

# Source catalog grid rendering functions
source "$(dirname "${BASH_SOURCE[0]}")/catalog/grid.sh"

# Grid rendering functions moved to catalog/grid.sh
# - draw_grid_row
# - redraw_catalog_page

display_catalog() {
    local title="$1"
    local use_gum=false
    local use_grid=false
    local all_results=()
    local page="${CATALOG_PAGE:-1}"
    local per_page=20
    shift

    # Check if 'gum' is explicitly requested via argument
    if [ "$1" = "gum" ]; then
        use_gum=true
        shift
    fi

    # Grid mode is enabled via the CLI --grid flag
    if [ "$USE_GRID_MODE" = "true" ]; then
        use_grid=true
    fi
    
    # Store original arguments for pagination navigation
    local original_args=("$@")
    
    echo -e "${BOLD}${YELLOW}$title${RESET}\n"
    
    # Initialize termflix directories
    init_termflix_dirs
    
    # Generate cache key from function names and arguments
    local cache_key=$(generate_cache_key "$title" "${original_args[@]}")
    local cache_dir=$(get_cache_dir)
    local cache_file="$cache_dir/catalog_${cache_key}.txt"
    
    # Check if cache is valid (less than 1 hour old)
    # Also invalidate if cache contains legacy "YTSRS" sources (we now use "YTS")
    # or if result count is suspicious (999 usually implies cache error)
    if [ -f "$cache_file" ] && (grep -q "YTSRS" "$cache_file" || grep -q "No Poster" "$cache_file"); then
         rm -f "$cache_file"
    fi

    if is_cache_valid "$cache_file" 1200; then
        echo -e "${CYAN}Loading from cache...${RESET}"
        # Read results from cache
        local result_count=0
        if [ -f "$cache_file" ] && [ -s "$cache_file" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                if [ -n "$line" ] && echo "$line" | grep -q '|'; then
                    all_results+=("$line")
                    result_count=$((result_count + 1))
                fi
            done < "$cache_file"
        fi
        
        if [ ${#all_results[@]} -gt 0 ]; then
            # Check if results are already grouped (contain COMBINED entries)
            local is_grouped=false
            for result in "${all_results[@]}"; do
                IFS='|' read -r result_source _ <<< "$result"
                if [[ "$result_source" == "COMBINED" ]]; then
                    is_grouped=true
                    break
                fi
            done
            
            if [ "$is_grouped" = true ]; then
                printf "\r${GREEN}✓ Loaded ${result_count} grouped results from cache${RESET}                    \n"
            else
                printf "\r${GREEN}✓ Loaded ${result_count} results from cache${RESET}                    \n"
            fi
            # Skip to pagination logic
            goto_pagination=true
        else
            goto_pagination=false
        fi
    else
        goto_pagination=false
    fi
    
    # Collect results from all functions passed as arguments
    local temp_file=$(mktemp 2>/dev/null || echo "/tmp/torrent_catalog_$$")
    local args_copy=("$@")
    local arg_idx=0
    local ytsrs_pids=()
    local all_pids=()
    local func_names=()
    
    # Only fetch if cache was not used
    if [ "$goto_pagination" != "true" ]; then
        echo -e "${CYAN}Fetching data from sources...${RESET}"
        
        # SMART PREFETCH STRATEGY:
        # Phase 1: Load pages 1-5 synchronously (fast startup ~5 sec)
        # Phase 2: Background fetch pages 6-15 (10 more pages)
        # Midpoint triggers: At page 10→fetch 16-25, page 20→fetch 26-35, etc.
        
        local initial_pages=10          # Load 5 pages upfront (250 results)
        local batch_size=10
        local page_pids=()
        local page_files=()
        
        while [ $arg_idx -lt ${#args_copy[@]} ]; do
        local func="${args_copy[$arg_idx]}"
        arg_idx=$((arg_idx + 1))
        local source_name=$(get_source_name "$func")
        
        # === PHASE 1: Load First 5 Pages Synchronously ===
        # Load more upfront for better UX (250 results vs 100)
        local current_page_pids=()
        if [ $arg_idx -lt ${#args_copy[@]} ] && [[ "${args_copy[$arg_idx]}" =~ ^[0-9]+$ ]]; then
            local limit="${args_copy[$arg_idx]}"
            arg_idx=$((arg_idx + 1))
            
            # Fetch initial 5 pages
            for p in $(seq 1 $initial_pages); do
                local page_file="${temp_file}.${source_name}.page${p}"
                page_files+=("$page_file")
                ($func "$limit" "$p" >> "$page_file" 2>&1) &
                current_page_pids+=($!)
                page_pids+=($!)
            done
        else
            # Fetch initial 5 pages (no limit arg)
            for p in $(seq 1 $initial_pages); do
                local page_file="${temp_file}.${source_name}.page${p}"
                page_files+=("$page_file")
                ($func "$p" >> "$page_file" 2>&1) &
                current_page_pids+=($!)
                page_pids+=($!)
            done
        fi
        
        # Wait for initial pages with spinner
        local spinner_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
        local spinner_idx1=0
        local spinner_idx2=0
        (
            while true; do
                local any_running=false
                for pid in "${current_page_pids[@]}"; do
                    if kill -0 "$pid" 2>/dev/null; then
                        any_running=true
                        break
                    fi
                done
                [ "$any_running" = false ] && break
                printf "\r${MAGENTA}${spinner_chars[$spinner_idx1]}${CYAN}${spinner_chars[$spinner_idx2]}${RESET} Loading ${PINK}${source_name}${RESET} (pages 1-5)..."
                spinner_idx1=$(( (spinner_idx1 - 1 + ${#spinner_chars[@]}) % ${#spinner_chars[@]} ))
                spinner_idx2=$(( (spinner_idx2 + 1) % ${#spinner_chars[@]} ))
                sleep 0.1
            done
            printf "\r${GREEN}✓${RESET} Loaded ${PINK}${source_name}${RESET} (pages 1-5)                    \n"
        ) &
        local spinner_pid=$!
        
        # Wait for initial pages
        for pid in "${current_page_pids[@]}"; do
            wait "$pid" 2>/dev/null || true
        done
        kill "$spinner_pid" 2>/dev/null || true
        wait "$spinner_pid" 2>/dev/null || true
        
        # === PHASE 2: Background Prefetch Pages 6-15 ===
        local batch_end=$((initial_pages + batch_size))
        echo -e "${GRAY}📥 Prefetching pages 11-${batch_end} in background...${RESET}"
        
        (
            for p in $(seq $((initial_pages + 1)) $batch_end); do
                # Append directly to main temp file (not individual page files)
                if [ $arg_idx -gt 0 ] && [[ -n "${limit:-}" ]]; then
                    $func "$limit" "$p" >> "$temp_file" 2>&1
                else
                    $func "$p" >> "$temp_file" 2>&1
                fi
            done
        ) &
        local prefetch_pid=$!
        
        # Export state for navigation handler and midpoint trigger
        export TERMFLIX_PREFETCH_PID=$prefetch_pid
        export TERMFLIX_BATCH_END=$batch_end
        export TERMFLIX_SOURCE_NAME="$source_name"
        export TERMFLIX_FUNC_NAME="$func"
        export TERMFLIX_FUNC_LIMIT="${limit:-}"
        export TERMFLIX_TEMP_FILE="$temp_file"
        export TERMFLIX_INITIAL_PAGES=$initial_pages
    done
        
        # Combine all page files into one temp file
        for page_file in "${page_files[@]}"; do
            if [ -f "$page_file" ]; then
                cat "$page_file" >> "$temp_file" 2>/dev/null || true
                rm -f "$page_file" 2>/dev/null || true
            fi
        done
        
        printf "\r${GREEN}✓ Fetched all pages${RESET}                    \n"
        
        
        echo -e "${CYAN}Parsing results...${RESET}"
        
        # Read results from temp file
        local result_count=0
        if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                if [ -n "$line" ] && echo "$line" | grep -q '|'; then
                    all_results+=("$line")
                    result_count=$((result_count + 1))
                    # Show progress while parsing
                    if [ $((result_count % 5)) -eq 0 ]; then
                        printf "\r${CYAN}Parsing results...${RESET} [%d found]" "$result_count"
                    fi
                fi
            done < "$temp_file"
        fi
        
        # DON'T delete temp file - background fetch needs to append to it!
        # rm -f "$temp_file" 2>/dev/null
        
        printf "\r${GREEN}✓ Parsed ${result_count} results${RESET}                    \n"
    fi
    
    if [ ${#all_results[@]} -eq 0 ]; then
        echo -e "${RED}No results found${RESET}"
        echo -e "${YELLOW}Note:${RESET} This might be due to API timeouts or rate limiting."
        echo "Try again in a moment or use: ${CYAN}torrent search \"query\"${RESET}"
        return 1
    fi
    
    echo  # Blank line before results
    
    # Group results BEFORE caching (only if not already grouped)
    local needs_grouping=true
    for result in "${all_results[@]}"; do
        IFS='|' read -r result_source _ <<< "$result"
        if [[ "$result_source" == "COMBINED" ]]; then
            needs_grouping=false
            break
        fi
    done
    
    
    if [ "$needs_grouping" = true ] && [ ${#all_results[@]} -gt 0 ]; then
        printf "${CYAN}Grouping results...${RESET}"
        local grouped_results=()
        local group_input=$(mktemp)
        printf "%s\n" "${all_results[@]}" > "$group_input"
        
        # Call group_results.py to combine duplicate movies from different sources
        local group_script="${TERMFLIX_SCRIPTS_DIR}/group_results.py"
        if [[ -f "$group_script" ]] && command -v python3 &>/dev/null; then
            local group_output=$(python3 "$group_script" < "$group_input" 2>/dev/null)
            if [ -n "$group_output" ]; then
                while IFS= read -r line || [ -n "$line" ]; do
                    grouped_results+=("$line")
                done <<< "$group_output"
                all_results=("${grouped_results[@]}")
            fi
        fi
        rm -f "$group_input"
        printf "\r${GREEN}✓ Grouped ${#all_results[@]} results${RESET}                    \n"
    fi
    
        
        # Check if results are COMBINED (already have posters from source APIs)
        local has_combined=false
        for result in "${all_results[@]:0:1}"; do
            IFS='|' read -r result_source _ <<< "$result"
            if [[ "$result_source" == "COMBINED" ]]; then
                has_combined=true
                break
            fi
        done
        
        # Skip poster enrichment for COMBINED entries (they already have posters)
        # Only enrich non-COMBINED entries with missing posters
        if [ "$has_combined" = false ] && [ ${#all_results[@]} -gt 0 ]; then
            printf "${CYAN}Fetching posters...${RESET}"
            # Add timeout to prevent hanging
            timeout 10s bash -c "source '$BASH_SOURCE' 2>/dev/null; enrich_missing_posters all_results 20" 2>/dev/null || true
            printf "\r${GREEN}✓ Enriched posters${RESET}                    \n"
        fi
        
        # Save GROUPED results to cache (after grouping and enrichment)
        if [ ${#all_results[@]} -gt 0 ]; then
            printf "%s\n" "${all_results[@]}" > "$cache_file" 2>/dev/null
        fi


    # Use gum interface if explicitly requested
    if [ "$use_gum" = true ]; then
        display_catalog_gum "$title" "${original_args[@]}"
        return $?
    fi

    # Use poster grid interface if grid mode is enabled
    if [ "$use_grid" = true ]; then
        # Pass results by reference into grid renderer
        local grid_results_ref="catalog_grid_results_$$"
        # shellcheck disable=SC2034  # referenced via eval in grid module
        eval "local -a ${grid_results_ref}=()"
        eval "${grid_results_ref}=(\"\${all_results[@]}\")"
        display_catalog_grid_mode "$title" "$grid_results_ref"
        return $?
    fi

    # FZF Catalog Logic - Page-Based Navigation with Background Prefetch
    # -------------------------------------------------------------------------
    
    local total_pages_loaded=10  # Initial pages loaded
    local current_page=1
    local items_per_page=50
    
    # Check for saved cursor position (from season picker return)
    local last_selected_index=1
    if [[ -f "/tmp/termflix_last_index" ]]; then
        local saved_idx
        saved_idx=$(cat "/tmp/termflix_last_index" 2>/dev/null)
        [[ "$saved_idx" =~ ^[0-9]+$ ]] && last_selected_index="$saved_idx"
        rm -f "/tmp/termflix_last_index"
    fi
    
    local skip_reload=false
    
    while true; do
        # CHECK: Reload if background fetch completed (check BEFORE showing FZF)
        # Skip reload check if just returning from stage 2 (Ctrl+H)
        if [[ "$skip_reload" != "true" ]] && [ -n "${TERMFLIX_PREFETCH_PID:-}" ]; then
            if ! kill -0 "$TERMFLIX_PREFETCH_PID" 2>/dev/null; then
                # Background complete - reload
                local temp_combined="${TERMFLIX_TEMP_FILE:-$temp_file}"
                if [[ -f "$temp_combined" ]]; then
                    all_results=()
                    while IFS= read -r line || [ -n "$line" ]; do
                        if [ -n "$line" ] && echo "$line" | grep -q '|'; then
                            all_results+=("$line")
                        fi
                    done < "$temp_combined"
                    
                    # Trigger next batch
                    if [[ "${TERMFLIX_NO_MORE_PAGES:-}" != "true" ]]; then
                        local next_start=$((TERMFLIX_BATCH_END + 1))
                        local next_end=$((next_start + 9))
                        ( for p in $(seq $next_start $next_end); do
                            if [[ -n "${TERMFLIX_FUNC_LIMIT}" ]]; then
                                ${TERMFLIX_FUNC_NAME} "${TERMFLIX_FUNC_LIMIT}" "$p" >> "${TERMFLIX_TEMP_FILE}" 2>&1
                            else
                                ${TERMFLIX_FUNC_NAME} "$p" >> "${TERMFLIX_TEMP_FILE}" 2>&1
                            fi
                        done ) &
                        export TERMFLIX_PREFETCH_PID=$!
                        export TERMFLIX_BATCH_END=$next_end
                    fi
                fi
            fi
        fi
        
        # Reset skip flag after first iteration
        skip_reload=false
        
        # Calculate total available pages
        local total_items=${#all_results[@]}
        local total_pages=$(( (total_items + items_per_page - 1) / items_per_page ))
        [[ $total_pages -lt 1 ]] && total_pages=1
        
        # DEBUG: Log item counts (only if DEBUG_MODE=1)
        if [[ "${DEBUG_MODE:-0}" == "1" ]]; then
            echo "[DEBUG] Current page: $current_page | Total items: $total_items | Total pages: $total_pages | Background PID: ${TERMFLIX_PREFETCH_PID:-none}" >&2
        fi
        
        # Add "+" if background is still fetching
        local total_display="$total_pages"
        if [ -n "${TERMFLIX_PREFETCH_PID:-}" ]; then
            if kill -0 "$TERMFLIX_PREFETCH_PID" 2>/dev/null; then
                total_display="${total_pages}+"
                [[ "${DEBUG_MODE:-0}" == "1" ]] && echo "[DEBUG] Background still running, showing ${total_pages}+" >&2
            else
                [[ "${DEBUG_MODE:-0}" == "1" ]] && echo "[DEBUG] Background completed" >&2
            fi
        fi
        
        # Slice current page
        local start_idx=$(( (current_page - 1) * items_per_page ))
        local page_results=("${all_results[@]:$start_idx:$items_per_page}")
        
        [[ "${DEBUG_MODE:-0}" == "1" ]] && echo "[DEBUG] Sliced page $current_page: start_idx=$start_idx, showing ${#page_results[@]} items" >&2
        
        # Show FZF with current page only
        # Mark context as catalog (non-search) for Stage 2 preview
        # BUT preserve existing "search" context if set (e.g., from Ctrl+F)
        if [[ "${TERMFLIX_STAGE1_CONTEXT:-}" != "search" ]]; then
            export TERMFLIX_STAGE1_CONTEXT="catalog"
        fi
        local selection_line
        selection_line=$(show_fzf_catalog "$title" page_results "$current_page" "$total_display" "$last_selected_index")
        local fzf_ret=$?

        # Debug logging
        echo "$(date): show_fzf_catalog returned $fzf_ret" >> /tmp/termflix_trace.log

        # Handle category switching and page navigation
        case $fzf_ret in
            101) return 101 ;;  # Movies
            102) return 102 ;;  # Shows
            103) return 103 ;;  # Watchlist
            104) return 104 ;;  # Type dropdown
            105) return 105 ;;  # Sort dropdown
            106) return 106 ;;  # Genre dropdown
            109) return 109 ;;  # Refresh
            110) return 110 ;;  # Year dropdown
            111) return 111 ;;  # Season Picker
            107)  # Next page (>)
                if [[ $current_page -lt $total_pages ]]; then
                    ((current_page++))
                fi
                continue
                ;;
            108)  # Previous page (<)
                if [[ $current_page -gt 1 ]]; then
                    ((current_page--))
                fi
                continue
                ;;
        esac
        
        # Extract selection index for cursor restoration
        if [ -n "$selection_line" ]; then
            local sel_idx
            sel_idx=$(echo "$selection_line" | cut -d'|' -f2)
            [[ "$sel_idx" =~ ^[0-9]+$ ]] && last_selected_index="$sel_idx"
            
            handle_fzf_selection "$selection_line"
            local ret_code=$?
            
            if [[ $ret_code -eq 10 ]]; then
                # User pressed Ctrl+H / Back - skip reload on next iteration for speed
                skip_reload=true
                continue
            elif [[ $ret_code -eq 0 ]]; then
                # Successful stream - return to catalog list
                continue
            else
                # Error, cancel or metadata failure - just go back to list
                continue
            fi
        else
            # No selection - cancelled
            break
        fi
        
        # After user action, check if background fetch completed
        # If yes, reload all results and restart with cursor preserved
        local should_restart=false
        
        if [ -n "${TERMFLIX_PREFETCH_PID:-}" ]; then
            # Check if background fetch finished
            if ! kill -0 "$TERMFLIX_PREFETCH_PID" 2>/dev/null; then
                # Background complete - reload data
                local temp_combined="${TERMFLIX_TEMP_FILE:-$temp_file}"
                if [[ -f "$temp_combined" ]]; then
                    all_results=()
                    while IFS= read -r line || [ -n "$line" ]; do
                        if [ -n "$line" ] && echo "$line" | grep -q '|'; then
                            all_results+=("$line")
                        fi
                    done < "$temp_combined"
                    
                    # Update loaded page count
                    total_pages_loaded=$(( ${#all_results[@]} / 50 ))
                    [[ $total_pages_loaded -lt 1 ]] && total_pages_loaded=1
                    
                    # Trigger next batch fetch if not at end
                    if [[ "${TERMFLIX_NO_MORE_PAGES:-}" != "true" ]]; then
                        local next_batch_start=$((TERMFLIX_BATCH_END + 1))
                        local next_batch_end=$((next_batch_start + 9))
                        
                        (  # Background fetch next 10 pages
                            for p in $(seq $next_batch_start $next_batch_end); do
                                if [[ -n "${TERMFLIX_FUNC_LIMIT}" ]]; then
                                    ${TERMFLIX_FUNC_NAME} "${TERMFLIX_FUNC_LIMIT}" "$p" >> "${TERMFLIX_TEMP_FILE}" 2>&1
                                else
                                    ${TERMFLIX_FUNC_NAME} "$p" >> "${TERMFLIX_TEMP_FILE}" 2>&1
                                fi
                            done
                        ) &
                        
                        export TERMFLIX_PREFETCH_PID=$!
                        export TERMFLIX_BATCH_END=$next_batch_end
                    fi
                    
                    # Restart FZF with new data
                    should_restart=true
                fi
            fi
        fi
        
        # If background completed, restart to show new data
        if [ "$should_restart" = true ]; then
            continue
        fi
    done
}

# ============================================================
# CATALOG FETCHING LOGIC - Moved to catalog/fetching.sh
# ============================================================
# Functions now sourced from: modules/catalog/fetching.sh
# - get_latest_movies
# - get_trending_movies
# - get_popular_movies
# - get_latest_shows
# - get_catalog_by_genre
# - get_new_48h_movies
