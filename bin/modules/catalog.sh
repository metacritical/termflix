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
    local all_results=()
    local page="${CATALOG_PAGE:-1}"
    local per_page=20
    shift

    # Check if 'gum' is the next argument
    if [ "$1" = "gum" ]; then
        use_gum=true
        shift
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
        echo -e "${CYAN}Fetching data from sources (all pages)...${RESET}"
        
        # CRITICAL: Fetch ALL pages at once and cache in memory
        # Fetch pages 1-10 in parallel to get all results
        local max_pages=10
        local page_pids=()
        local page_files=()
        
        while [ $arg_idx -lt ${#args_copy[@]} ]; do
        local func="${args_copy[$arg_idx]}"
        arg_idx=$((arg_idx + 1))
        local source_name=$(get_source_name "$func")
        
        # Call the function with remaining arguments
        local current_page_pids=()
        if [ $arg_idx -lt ${#args_copy[@]} ] && [[ "${args_copy[$arg_idx]}" =~ ^[0-9]+$ ]]; then
            local limit="${args_copy[$arg_idx]}"
            arg_idx=$((arg_idx + 1))
            
            # Fetch all pages (1-10) in parallel for this function
            for p in $(seq 1 $max_pages); do
                local page_file="${temp_file}.${source_name}.page${p}"
                page_files+=("$page_file")
                ($func "$limit" "$p" >> "$page_file" 2>&1) &
                current_page_pids+=($!)
                page_pids+=($!)
            done
        else
            # Fetch all pages (1-10) in parallel for this function
            for p in $(seq 1 $max_pages); do
                local page_file="${temp_file}.${source_name}.page${p}"
                page_files+=("$page_file")
                ($func "$p" >> "$page_file" 2>&1) &
                current_page_pids+=($!)
                page_pids+=($!)
            done
        fi
        
        # Wait for this source's page fetches to complete with dual spinner (spinning in opposite directions)
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
                # Charm-style dual spinner: magenta goes backward, cyan goes forward
                printf "\r${MAGENTA}${spinner_chars[$spinner_idx1]}${CYAN}${spinner_chars[$spinner_idx2]}${RESET} Fetching from ${PINK}${source_name}${RESET}..."
                spinner_idx1=$(( (spinner_idx1 - 1 + ${#spinner_chars[@]}) % ${#spinner_chars[@]} ))
                spinner_idx2=$(( (spinner_idx2 + 1) % ${#spinner_chars[@]} ))
                sleep 0.1
            done
            printf "\r${GREEN}✓${RESET} Fetched from ${PINK}${source_name}${RESET}                    \n"
        ) &
        local spinner_pid=$!
        
        # Wait for this source's page fetches to complete
        for pid in "${current_page_pids[@]}"; do
            wait "$pid" 2>/dev/null || true
        done
        
        # Stop spinner
        kill "$spinner_pid" 2>/dev/null || true
        wait "$spinner_pid" 2>/dev/null || true
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
        
        rm -f "$temp_file" 2>/dev/null
        
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
        local group_output=$(cat "$group_input" | group_results 2>/dev/null)
        if [ -n "$group_output" ]; then
             while IFS= read -r line || [ -n "$line" ]; do
                 grouped_results+=("$line")
             done <<< "$group_output"
             all_results=("${grouped_results[@]}")
        fi
        rm -f "$group_input"
        printf "\r${GREEN}✓ Grouped ${#all_results[@]} results${RESET}                    \n"
        
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
    fi

    # Use gum interface if requested
    if [ "$use_gum" = true ]; then
        display_catalog_gum "$title" "${original_args[@]}"
        return $?
    fi

    # FZF Catalog Logic
    # -------------------------------------------------------------------------
    # Use FZF for browsing, filtering, and Preview (replacing sidebar picker)
    
    # Pagination state
    local current_page=1
    local items_per_page=50
    local total_items=${#all_results[@]}
    local total_pages=$(( (total_items + items_per_page - 1) / items_per_page ))
    [[ $total_pages -lt 1 ]] && total_pages=1
    local last_selected_pos=1  # Track cursor position for restoration
    
    # FZF Catalog Logic with Navigation Loop
    # -------------------------------------------------------------------------
    while true; do
        # Slice array for current page
        local start_idx=$(( (current_page - 1) * items_per_page ))
        local page_results=("${all_results[@]:$start_idx:$items_per_page}")
        
        local selection_line
        selection_line=$(show_fzf_catalog "$title" page_results "$current_page" "$total_pages" "$last_selected_pos")
        local fzf_ret=$?
        
        # Handle category switching return codes (101-108)
        # Keybindings: ^O=Movies, ^S=Shows, ^W=Watchlist, ^T=Type, ^R=Sort, ^G=Genre, >/<=Page
        case $fzf_ret in
            101) return 101 ;;  # Movies (^O)
            102) return 102 ;;  # Shows (^S)
            103) return 103 ;;  # Watchlist (^W)
            104) return 104 ;;  # Type dropdown (^T)
            105) return 105 ;;  # Sort dropdown (^R)
            106) return 106 ;;  # Genre dropdown (^G)
            107)  # Next page (> or Ctrl+Right)
                if [[ $current_page -lt $total_pages ]]; then
                    ((current_page++))
                fi
                continue
                ;;
            108)  # Previous page (< or Ctrl+Left)
                if [[ $current_page -gt 1 ]]; then
                    ((current_page--))
                fi
                continue
                ;;
            1)   return 0 ;;    # FZF cancelled (Esc/Ctrl-C)
        esac
        
        # Normal selection handling (fzf_ret=0 with output)
        if [ -n "$selection_line" ]; then
             # Extract index from selection to remember cursor position
             # Format: "key|index|rest_data..."
             local sel_idx
             sel_idx=$(echo "$selection_line" | cut -d'|' -f2)
             [[ "$sel_idx" =~ ^[0-9]+$ ]] && last_selected_pos="$sel_idx"
             
             handle_fzf_selection "$selection_line"
             local ret_code=$?
             
             if [ $ret_code -eq 10 ]; then
                 # User pressed Ctrl+H / Back in nested picker -> Loop again
                 continue
             elif [ $ret_code -eq 0 ]; then
                 # Successful stream -> Exit function
                 return 0
             else
                 # Error or Cancel -> Break
                 break
             fi
        else
             # No selection -> cancelled
             break
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

