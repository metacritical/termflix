#!/usr/bin/env bash
#
# Termflix Gum Catalog Module
# Gum-based catalog display with no flicker
#

# Display catalog results using gum for a cleaner interface
display_catalog_gum() {
    local title="$1"
    local all_results=()
    local page="${CATALOG_PAGE:-1}"
    local per_page=20
    shift

    # Store original arguments for pagination navigation
    local original_args=("$@")

    # Initialize termflix directories
    init_termflix_dirs

    # Generate cache key from function names and arguments
    local cache_key=$(generate_cache_key "$title" "${original_args[@]}")
    local cache_dir=$(get_cache_dir)
    local cache_file="$cache_dir/catalog_${cache_key}.txt"

    # Check if cache is valid (less than 1 hour old)
    if is_cache_valid "$cache_file"; then
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
            printf "\r${GREEN}✓ Loaded ${result_count} results from cache${RESET}\n"
        fi
    else
        # Fetch results using the provided functions
        echo -e "${CYAN}Fetching data from sources...${RESET}"

        # Collect results from all functions passed as arguments
        local temp_file=$(mktemp 2>/dev/null || echo "/tmp/torrent_catalog_$$")
        local args_copy=("$@")
        local arg_idx=0

        while [ $arg_idx -lt ${#args_copy[@]} ]; do
            local func="${args_copy[$arg_idx]}"
            arg_idx=$((arg_idx + 1))
            local source_name=$(get_source_name "$func")

            if [ $arg_idx -lt ${#args_copy[@]} ] && [[ "${args_copy[$arg_idx]}" =~ ^[0-9]+$ ]]; then
                local limit="${args_copy[$arg_idx]}"
                arg_idx=$((arg_idx + 1))
                
                # Call function with limit and page parameters
                $func "$limit" "$page" >> "$temp_file" 2>/dev/null
            else
                # Call function with just page parameter
                $func "$page" >> "$temp_file" 2>/dev/null
            fi
        done

        # Read results from temp file
        local result_count=0
        if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                if [ -n "$line" ] && echo "$line" | grep -q '|'; then
                    all_results+=("$line")
                    result_count=$((result_count + 1))
                fi
            done < "$temp_file"
        fi

        rm -f "$temp_file" 2>/dev/null

        # Group results (only if not already grouped)
        local needs_grouping=true
        for result in "${all_results[@]}"; do
            IFS='|' read -r result_source _ <<< "$result"
            if [[ "$result_source" == "COMBINED" ]]; then
                needs_grouping=false
                break
            fi
        done

        if [ "$needs_grouping" = true ] && [ ${#all_results[@]} -gt 0 ]; then
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
            
            # Save grouped results to cache
            if [ ${#all_results[@]} -gt 0 ]; then
                printf "%s\n" "${all_results[@]}" > "$cache_file" 2>/dev/null
            fi
        fi
    fi

    if [ ${#all_results[@]} -eq 0 ]; then
        echo -e "${RED}No results found${RESET}"
        return 1
    fi

    # Calculate pagination
    local total="${#all_results[@]}"
    local total_pages=$(( (total + per_page - 1) / per_page ))

    # Store cached results in a variable name for later use
    local cached_results_var="cached_results_$$"
    eval "declare -a ${cached_results_var}=()"
    for result in "${all_results[@]}"; do
        eval "${cached_results_var}+=(\"\$result\")"
    done

    # Display using gum
    display_catalog_page_gum "$title" "$cached_results_var" "$page" "$per_page" "$total"
}

# Display a single page of catalog results using gum
display_catalog_page_gum() {
    local title="$1"
    local cached_results_ref="$2"
    local page="$3"
    local per_page="$4"
    local total="$5"

    # Get the cached results array
    eval "local all_results=(\"\${${cached_results_ref}[@]}\")"

    # Calculate pagination
    local total_pages=$(( (total + per_page - 1) / per_page ))
    local start_idx=$(( (page - 1) * per_page ))
    local end_idx=$(( start_idx + per_page ))
    if [ "$end_idx" -gt "$total" ]; then
        end_idx=$total
    fi

    # Prepare the data for gum table
    local table_data="ID|Title|Source|Quality|Size|Seeds\n"
    
    for ((i = start_idx; i < end_idx; i++)); do
        if [ $i -ge ${#all_results[@]} ]; then
            break
        fi
        
        local result="${all_results[$i]}"
        IFS='|' read -r source name magnet quality size extra poster_url <<< "$result"

        # Check if item is COMBINED
        if [[ "$source" == "COMBINED" ]]; then
            # Parse COMBINED format: COMBINED|Name|Sources^|Qualities^|Seeds^|Sizes^|Magnets^|Poster
            IFS='|' read -r _ c_name c_sources c_seeds c_qualities c_sizes c_magnets c_poster <<< "$result"
            local sources_arr=()
            local seeds_arr=()
            local qualities_arr=()
            IFS='^' read -ra sources_arr <<< "$c_sources"
            IFS='^' read -ra seeds_arr <<< "$c_seeds"
            IFS='^' read -ra qualities_arr <<< "$c_qualities"
            
            # Build source tags string
            local source_tags=""
            for src in "${sources_arr[@]}"; do
                case "$src" in
                    YTS) source_tags="${source_tags}[${GREEN}YTS${RESET}] " ;;
                    TPB) source_tags="${source_tags}[${YELLOW}TPB${RESET}] " ;;
                    EZTV) source_tags="${source_tags}[${BLUE}EZTV${RESET}] " ;;
                    1337x) source_tags="${source_tags}[${MAGENTA}1337x${RESET}] " ;;
                    *) source_tags="${source_tags}[${CYAN}${src}${RESET}] " ;;
                esac
            done
            source_tags=$(echo "$source_tags" | sed 's/[[:space:]]*$//')  # Trim trailing space
            
            # Use first quality as representative
            quality="${qualities_arr[0]:-N/A}"
            # Calculate max seeds
            local max_seeds=0
            for seed_str in "${seeds_arr[@]}"; do
                local seed_val=$(echo "$seed_str" | grep -oE '[0-9]+' | head -1)
                if [ -n "$seed_val" ] && [ "$seed_val" -gt "$max_seeds" ] 2>/dev/null; then
                    max_seeds=$seed_val
                fi
            done
            extra="$max_seeds seeds"
            source="$source_tags"
        else
            # Single source - color code the source
            local source_color="$CYAN"
            case "$source" in
                YTS) source_color="$GREEN" ;;
                TPB) source_color="$YELLOW" ;;
                EZTV) source_color="$BLUE" ;;
                1337x) source_color="$MAGENTA" ;;
            esac
            source="$(echo -e "${source_color}[$source]${RESET}")"
        fi

        # Truncate name if too long
        local display_name="${name:0:50}"
        if [ "${#name}" -gt 50 ]; then
            display_name="${display_name}..."
        fi

        local id=$((i + 1))
        table_data="${table_data}${id}|${display_name}|${source}|${quality}|${size}|${extra}\n"
    done

    # Use improved two-column layout with image support
    if command -v gum &>/dev/null; then
        echo -e "${BOLD}${YELLOW}$title${RESET}"
        echo -e "${CYAN}Page ${page} of ${total_pages}${RESET} | ${GREEN}Total results: ${total}${RESET}"
        echo

        # Calculate terminal dimensions for two-column layout
        local term_cols=$(tput cols 2>/dev/null || echo 80)
        local left_width=$((term_cols / 2 - 2))  # Leave some margin
        local right_start=$((left_width + 2))

        # Process results in pairs for two-column display
        for ((i = start_idx; i < end_idx; i+=2)); do
            # Left column item
            if [ $i -ge ${#all_results[@]} ]; then
                break
            fi

            local result_left="${all_results[$i]}"
            IFS='|' read -r source_left name_left magnet_left quality_left size_left extra_left poster_url_left <<< "$result_left"

            local display_name_left="${name_left:0:$((left_width/2))}"
            if [ "${#name_left}" -gt $((left_width/2)) ]; then
                display_name_left="${display_name_left}..."
            fi

            # Format source tags for left item
            local source_tags_left=""
            if [[ "$source_left" == "COMBINED" ]]; then
                IFS='|' read -r _ c_name_left c_sources_left c_seeds_left c_qualities_left c_sizes_left c_magnets_left c_poster_left <<< "$result_left"
                local sources_arr_left=()
                IFS='^' read -ra sources_arr_left <<< "$c_sources_left"
                for src in "${sources_arr_left[@]}"; do
                    case "$src" in
                        YTS) source_tags_left="${source_tags_left}[${GREEN}YTS${RESET}] " ;;
                        TPB) source_tags_left="${source_tags_left}[${YELLOW}TPB${RESET}] " ;;
                        EZTV) source_tags_left="${source_tags_left}[${BLUE}EZTV${RESET}] " ;;
                        1337x) source_tags_left="${source_tags_left}[${MAGENTA}1337x${RESET}] " ;;
                        *) source_tags_left="${source_tags_left}[${CYAN}${src}${RESET}] " ;;
                    esac
                done
                source_tags_left=$(echo "$source_tags_left" | sed 's/[[:space:]]*$//')
                name_left="$c_name_left"
                poster_url_left="$c_poster_left"
            else
                local source_color_left="$CYAN"
                case "$source_left" in
                    YTS) source_color_left="$GREEN" ;;
                    TPB) source_color_left="$YELLOW" ;;
                    EZTV) source_color_left="$BLUE" ;;
                    1337x) source_color_left="$MAGENTA" ;;
                esac
                source_tags_left="${source_color_left}[$source_left]${RESET}"
            fi

            # Right column item
            local result_right=""
            local display_name_right=""
            local source_tags_right=""
            local name_right=""
            local poster_url_right=""

            if [ $((i+1)) -lt $end_idx ] && [ $((i+1)) -lt ${#all_results[@]} ]; then
                result_right="${all_results[$((i+1))]}"
                IFS='|' read -r source_right name_right magnet_right quality_right size_right extra_right poster_url_right <<< "$result_right"

                display_name_right="${name_right:0:$((left_width/2))}"
                if [ "${#name_right}" -gt $((left_width/2)) ]; then
                    display_name_right="${display_name_right}..."
                fi

                # Format source tags for right item
                if [[ "$source_right" == "COMBINED" ]]; then
                    IFS='|' read -r _ c_name_right c_sources_right c_seeds_right c_qualities_right c_sizes_right c_magnets_right c_poster_right <<< "$result_right"
                    local sources_arr_right=()
                    IFS='^' read -ra sources_arr_right <<< "$c_sources_right"
                    for src in "${sources_arr_right[@]}"; do
                        case "$src" in
                            YTS) source_tags_right="${source_tags_right}[${GREEN}YTS${RESET}] " ;;
                            TPB) source_tags_right="${source_tags_right}[${YELLOW}TPB${RESET}] " ;;
                            EZTV) source_tags_right="${source_tags_right}[${BLUE}EZTV${RESET}] " ;;
                            1337x) source_tags_right="${source_tags_right}[${MAGENTA}1337x${RESET}] " ;;
                            *) source_tags_right="${source_tags_right}[${CYAN}${src}${RESET}] " ;;
                        esac
                    done
                    source_tags_right=$(echo "$source_tags_right" | sed 's/[[:space:]]*$//')
                    name_right="$c_name_right"
                    poster_url_right="$c_poster_right"
                else
                    local source_color_right="$CYAN"
                    case "$source_right" in
                        YTS) source_color_right="$GREEN" ;;
                        TPB) source_color_right="$YELLOW" ;;
                        EZTV) source_color_right="$BLUE" ;;
                        1337x) source_color_right="$MAGENTA" ;;
                    esac
                    source_tags_right="${source_color_right}[$source_right]${RESET}"
                fi
            fi

            # Display two items side by side with potential images
            local left_item="${BOLD}$((i+1)). ${display_name_left}${RESET}\n${source_tags_left}"
            if [[ -n "$quality_left" ]] && [[ "$quality_left" != "N/A" ]]; then
                left_item="${left_item} ${CYAN}${quality_left}${RESET}"
            fi
            if [[ -n "$size_left" ]] && [[ "$size_left" != "N/A" ]]; then
                left_item="${left_item} | ${size_left}"
            fi
            if [[ -n "$extra_left" ]] && [[ "$extra_left" != "N/A" ]]; then
                left_item="${left_item} | ${extra_left}"
            fi

            # Prepare right item info
            local right_item=""
            if [ -n "$result_right" ]; then
                local right_num=$((i+2))
                right_item="${BOLD}${right_num}. ${display_name_right}${RESET}\n${source_tags_right}"
                if [[ -n "$quality_right" ]] && [[ "$quality_right" != "N/A" ]]; then
                    right_item="${right_item} ${CYAN}${quality_right}${RESET}"
                fi
                if [[ -n "$size_right" ]] && [[ "$size_right" != "N/A" ]]; then
                    right_item="${right_item} | ${size_right}"
                fi
                if [[ -n "$extra_right" ]] && [[ "$extra_right" != "N/A" ]]; then
                    right_item="${right_item} | ${extra_right}"
                fi
            fi

            # Display with image support if available
            if [[ -n "$poster_url_left" ]] && [[ "$poster_url_left" != "N/A" ]]; then
                # Download left poster
                local temp_poster_left="${TMPDIR:-/tmp}/termflix_left_$$.jpg"
                if curl -s --max-time 5 "$poster_url_left" -o "$temp_poster_left" 2>/dev/null && [ -f "$temp_poster_left" ]; then
                    # Display left with image
                    if [[ "$TERM" == "xterm-kitty" ]] && command -v kitty &> /dev/null; then
                        # Print left info, then image, then right info
                        echo -e "$left_item"
                        kitty +kitten icat --align left --place "10x6@1x$((i%10+1))" "$temp_poster_left" 2>/dev/null || echo -e "$left_item"
                    elif command -v viu &> /dev/null; then
                        # Display with viu
                        echo -e "$left_item"
                        viu -w 10 -h 6 "$temp_poster_left" 2>/dev/null
                    else
                        echo -e "$left_item"
                    fi
                    rm -f "$temp_poster_left" 2>/dev/null
                else
                    echo -e "$left_item"
                fi
            else
                echo -e "$left_item"
            fi

            # Display right item (if exists) with potential image
            if [ -n "$result_right" ] && [[ -n "$poster_url_right" ]] && [[ "$poster_url_right" != "N/A" ]]; then
                # Download right poster
                local temp_poster_right="${TMPDIR:-/tmp}/termflix_right_$$.jpg"
                if curl -s --max-time 5 "$poster_url_right" -o "$temp_poster_right" 2>/dev/null && [ -f "$temp_poster_right" ]; then
                    # Display right with image
                    if [[ "$TERM" == "xterm-kitty" ]] && command -v kitty &> /dev/null; then
                        # Print right info, then image
                        echo -e "\033[${right_start}G$right_item"
                        # Position kitty image appropriately
                        kitty +kitten icat --align left --place "10x6@${right_start}x$((i%10+1))" "$temp_poster_right" 2>/dev/null || echo -e "\033[${right_start}G$right_item"
                    elif command -v viu &> /dev/null; then
                        # Display with viu
                        echo -e "\033[${right_start}G$right_item"
                        # Move to appropriate position and display viu
                        echo -ne "\033[s"  # Save cursor position
                        echo -ne "\033[1C\033[1B"  # Move right and down
                        viu -w 10 -h 6 "$temp_poster_right" 2>/dev/null
                        echo -ne "\033[u"  # Restore cursor position
                    else
                        echo -e "\033[${right_start}G$right_item"
                    fi
                    rm -f "$temp_poster_right" 2>/dev/null
                else
                    echo -e "\033[${right_start}G$right_item"
                fi
            elif [ -n "$result_right" ]; then
                echo -e "\033[${right_start}G$right_item"
            fi

            echo  # Add spacing between rows
        done
    else
        # Fallback to basic display if gum is not available
        echo -e "${BOLD}${YELLOW}$title${RESET}"
        echo -e "${CYAN}Page ${page} of ${total_pages}${RESET} | ${GREEN}Total results: ${total}${RESET}"
        echo
        for ((i = start_idx; i < end_idx; i++)); do
            if [ $i -ge ${#all_results[@]} ]; then
                break
            fi

            local result="${all_results[$i]}"
            IFS='|' read -r source name magnet quality size extra poster_url <<< "$result"

            if [[ "$source" == "COMBINED" ]]; then
                IFS='|' read -r _ c_name c_sources c_seeds c_qualities c_sizes c_magnets c_poster <<< "$result"
                local sources_arr=()
                IFS='^' read -ra sources_arr <<< "$c_sources"
                # Build source tags string
                local source_tags=""
                for src in "${sources_arr[@]}"; do
                    case "$src" in
                        YTS) source_tags="${source_tags}[${GREEN}YTS${RESET}] " ;;
                        TPB) source_tags="${source_tags}[${YELLOW}TPB${RESET}] " ;;
                        EZTV) source_tags="${source_tags}[${BLUE}EZTV${RESET}] " ;;
                        1337x) source_tags="${source_tags}[${MAGENTA}1337x${RESET}] " ;;
                        *) source_tags="${source_tags}[${CYAN}${src}${RESET}] " ;;
                    esac
                done
                source_tags=$(echo "$source_tags" | sed 's/[[:space:]]*$//')

                printf "%2d. %-50s %s %s %s %s\n" $((i+1)) "${name:0:50}..." "$source_tags" "$quality" "$size" "$extra"
            else
                local source_color="$CYAN"
                case "$source" in
                    YTS) source_color="$GREEN" ;;
                    TPB) source_color="$YELLOW" ;;
                    EZTV) source_color="$BLUE" ;;
                    1337x) source_color="$MAGENTA" ;;
                esac
                printf "%2d. %-50s ${source_color}[%s]${RESET} %s %s %s\n" $((i+1)) "${name:0:50}..." "$source" "$quality" "$size" "$extra"
            fi
        done
    fi

    # Interactive selection
    if [ -t 0 ]; then
        echo
        echo -e "${CYAN}Select a torrent (1-${total}) or 'q' to quit:${RESET} "
        
        if command -v gum &>/dev/null; then
            # Use gum input for a better experience
            local selection
            selection=$(gum input --placeholder="Enter number (1-${total}) or 'q' to quit" --value="" 2>/dev/null)
            
            if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
                unset CATALOG_PAGE
                return 0
            fi
            
            if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$total" ]; then
                local selected_idx=$((selection - 1))
                local selected_result
                eval "selected_result=\"\${${cached_results_ref}[$selected_idx]}\""
                
                IFS='|' read -r source name magnet quality size extra poster_url <<< "$selected_result"

                # Check if item is COMBINED
                if [[ "$source" == "COMBINED" ]]; then
                    # Format: COMBINED|Name|Sources|Qualities|Seeds|Sizes|Magnets|Poster
                    IFS='|' read -r _ c_name c_sources c_qualities c_seeds c_sizes c_magnets c_poster <<< "$selected_result"
                    local sources_arr=()
                    local seeds_arr=()
                    local qualities_arr=()
                    local sizes_arr=()
                    local magnets_arr=()
                    IFS='^' read -ra sources_arr <<< "$c_sources"
                    IFS='^' read -ra seeds_arr <<< "$c_seeds"
                    IFS='^' read -ra qualities_arr <<< "$c_qualities"
                    IFS='^' read -ra sizes_arr <<< "$c_sizes"
                    IFS='^' read -ra magnets_arr <<< "$c_magnets"

                    # Use the existing gum-based selection for multiple sources
                    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                    echo -e "${CYAN}Multiple versions found for:${RESET} ${BOLD}${YELLOW}$c_name${RESET}"
                    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
                    
                    local selected_idx=0
                    
                    if command -v gum &> /dev/null; then
                         echo -e "${GREEN}Select a version:${RESET}"
                         # Create a numbered list for gum
                         local gum_opts=()
                         for i in "${!sources_arr[@]}"; do
                             local src="${sources_arr[$i]}"
                             local qty="${qualities_arr[$i]}"
                             local sz="${sizes_arr[$i]}"
                             local sd="${seeds_arr[$i]}"
                             gum_opts+=("$((i+1)). [${src}] ${qty} - ${sz} (${sd} seeds)")
                         done
                         local choice=$(printf "%s\n" "${gum_opts[@]}" | gum choose --height=10 --cursor="➤ " --header="Available Versions" --header.foreground="212")
                         
                         if [ -n "$choice" ]; then
                             # Extract number from choice (format: "1. ...")
                             local choice_num=$(echo "$choice" | grep -oE '^([0-9]+)' | head -1)
                             if [ -n "$choice_num" ] && [ "$choice_num" -ge 1 ] && [ "$choice_num" -le "${#sources_arr[@]}" ]; then
                                 selected_idx=$((choice_num - 1))
                             else
                                 return 1
                             fi
                         else
                             return 1
                         fi
                    else
                        # Fallback to manual selection
                        for i in "${!sources_arr[@]}"; do
                            local src="${sources_arr[$i]}"
                            local qty="${qualities_arr[$i]}"
                            local sz="${sizes_arr[$i]}"
                            local sd="${seeds_arr[$i]}"
                            echo "$((i+1)). [${src}] ${qty} - ${sz} (${sd} seeds)"
                        done
                        echo -n "Select (1-${#sources_arr[@]}): "
                        read -r choice_num
                        if [[ "$choice_num" =~ ^[0-9]+$ ]] && [ "$choice_num" -ge 1 ] && [ "$choice_num" -le "${#sources_arr[@]}" ]; then
                            selected_idx=$((choice_num - 1))
                        else
                            return 1
                        fi
                    fi

                    # Use selected magnet and other details
                    source="${sources_arr[$selected_idx]}"
                    magnet="${magnets_arr[$selected_idx]}"
                    quality="${qualities_arr[$selected_idx]}"
                    size="${sizes_arr[$selected_idx]}"
                    name="$c_name"
                fi

                # Validate and stream
                magnet=$(echo "$magnet" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [ -z "$magnet" ] || [[ ! "$magnet" =~ ^magnet: ]]; then
                    echo -e "${RED}Error:${RESET} Invalid or missing magnet link for selected torrent"
                    return 1
                fi

                echo
                echo -e "${GREEN}Streaming:${RESET} $name"
                echo

                # Stream the selected torrent
                stream_torrent "$magnet" "" false false
            else
                echo -e "${RED}Invalid selection${RESET}"
                display_catalog_page_gum "$title" "$cached_results_var" "$page" "$per_page" "$total"
            fi
        else
            # Fallback to basic selection
            read -r selection
            if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
                unset CATALOG_PAGE
                return 0
            fi
            
            if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$total" ]; then
                local selected_idx=$((selection - 1))
                local selected_result
                eval "selected_result=\"\${${cached_results_ref}[$selected_idx]}\""
                
                IFS='|' read -r source name magnet quality size extra poster_url <<< "$selected_result"

                # Check if item is COMBINED
                if [[ "$source" == "COMBINED" ]]; then
                    # Handle COMBINED entry (same logic as above)
                    IFS='|' read -r _ c_name c_sources c_qualities c_seeds c_sizes c_magnets c_poster <<< "$selected_result"
                    local sources_arr=()
                    local seeds_arr=()
                    local qualities_arr=()
                    local sizes_arr=()
                    local magnets_arr=()
                    IFS='^' read -ra sources_arr <<< "$c_sources"
                    IFS='^' read -ra seeds_arr <<< "$c_seeds"
                    IFS='^' read -ra qualities_arr <<< "$c_qualities"
                    IFS='^' read -ra sizes_arr <<< "$c_sizes"
                    IFS='^' read -ra magnets_arr <<< "$c_magnets"

                    # Fallback to manual selection for multiple sources
                    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                    echo -e "${CYAN}Multiple versions found for:${RESET} ${BOLD}${YELLOW}$c_name${RESET}"
                    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
                    
                    for i in "${!sources_arr[@]}"; do
                        local src="${sources_arr[$i]}"
                        local qty="${qualities_arr[$i]}"
                        local sz="${sizes_arr[$i]}"
                        local sd="${seeds_arr[$i]}"
                        echo "$((i+1)). [${src}] ${qty} - ${sz} (${sd} seeds)"
                    done
                    echo -n "Select (1-${#sources_arr[@]}): "
                    read -r choice_num
                    if [[ "$choice_num" =~ ^[0-9]+$ ]] && [ "$choice_num" -ge 1 ] && [ "$choice_num" -le "${#sources_arr[@]}" ]; then
                        selected_idx=$((choice_num - 1))
                    else
                        return 1
                    fi

                    source="${sources_arr[$selected_idx]}"
                    magnet="${magnets_arr[$selected_idx]}"
                    quality="${qualities_arr[$selected_idx]}"
                    size="${sizes_arr[$selected_idx]}"
                    name="$c_name"
                fi

                # Validate and stream
                magnet=$(echo "$magnet" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [ -z "$magnet" ] || [[ ! "$magnet" =~ ^magnet: ]]; then
                    echo -e "${RED}Error:${RESET} Invalid or missing magnet link for selected torrent"
                    return 1
                fi

                echo
                echo -e "${GREEN}Streaming:${RESET} $name"
                echo

                # Stream the selected torrent
                stream_torrent "$magnet" "" false false
            else
                echo -e "${RED}Invalid selection${RESET}"
                display_catalog_page_gum "$title" "$cached_results_var" "$page" "$per_page" "$total"
            fi
        fi
    fi
}

export -f display_catalog_gum display_catalog_page_gum