#!/usr/bin/env bash
#
# Termflix Catalog Module
# Grid rendering, catalog display, and browsing functions
#

# Draw a row of up to 3 items in a grid
# Offline rendering: Pre-render images, then draw row-by-row with proper cursor positioning
draw_grid_row() {
    local start_row="$1"
    local start_index="$2"
    local num_cols="$3"
    shift 3
    local items=("$@")
    
    local col_width=40  # Approximate column width in characters
    local img_width=20
    local img_height=15
    local row_height=21  # Total height for one row (image + 3 text lines + spacing)
    
    # Calculate column positions based on terminal width
    # Ensure proper spacing: each column needs at least img_width + padding
    local term_cols=$(tput cols)
    # Calculate spacing to evenly distribute columns with proper padding
    # Each column needs ~40 chars (20 for image + 20 for text), but we'll use dynamic spacing
    local total_cols_needed=$((num_cols * 40))
    local spacing
    if [ "$total_cols_needed" -le "$term_cols" ]; then
        # We have enough space, use even distribution
        spacing=$((term_cols / num_cols))
    else
        # Not enough space, use minimum spacing
        spacing=40
    fi
    local col_positions=()
    for ((c=0; c<num_cols; c++)); do
        col_positions+=($((c * spacing)))
    done

    # Pass 1: Pre-download all images in parallel
    local temp_dir="${TMPDIR:-/tmp}/torrent_posters_$$"
    mkdir -p "$temp_dir" 2>/dev/null
    
    local pids=()
    local image_files=()
    
    for i in "${!items[@]}"; do
        local result="${items[$i]}"
        IFS='|' read -r source name magnet quality size extra poster_url <<< "$result"
        
        # Handle COMBINED entries
        if [[ "$source" == "COMBINED" ]]; then
            # COMBINED|Name|Sources|Seeds|Qualities|Sizes|Magnets|Poster
            IFS='|' read -r _ c_name _ _ _ _ _ c_poster <<< "$result"
            name="$c_name"
            poster_url="$c_poster"
        fi
        
        if [[ -n "$poster_url" ]] && [[ "$poster_url" != "N/A" ]]; then
            # Check if it's already a cached file path
            if [ -f "$poster_url" ]; then
                # It's a file path, use it directly
                image_files[$i]="$poster_url"
            else
                # It's a URL, download it
                # Use md5 on macOS, md5sum on Linux
                local hash=$(echo "$poster_url" | md5 2>/dev/null || echo "$poster_url" | md5sum 2>/dev/null | cut -d' ' -f1)
                local image_file="${temp_dir}/poster_$(echo "$hash" | cut -c1-8).jpg"
                image_files[$i]="$image_file"
                
                # Download in background if not already cached
                if [ ! -f "$image_file" ]; then
                    ( curl -s --max-time 5 "$poster_url" -o "$image_file" 2>/dev/null ) &
                    pids+=($!)
                fi
            fi
        else
            image_files[$i]=""
        fi
    done
    
    # Wait for all downloads to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null
    done
    
    # Pass 2: Pre-render all images offline - capture each line separately
    # Store rendered lines: image_lines[item_index][row_index] = line_content
    declare -a has_image=()
    declare -a is_kitty=()
    # Use associative array-like structure with temp files for each item's lines
    local image_line_files=()
    
    for i in "${!items[@]}"; do
        local image_file="${image_files[$i]}"
        has_image[$i]=0
        is_kitty[$i]=0
        image_line_files[$i]=""
        
        if [[ -n "$image_file" ]] && [[ -f "$image_file" ]]; then
            # Check if we're using kitty (which handles positioning differently)
            if [[ "$TERM" == "xterm-kitty" ]] && command -v kitty &> /dev/null; then
                is_kitty[$i]=1
                has_image[$i]=1
            elif check_viu >/dev/null 2>&1; then
                # Pre-render image with viu and capture output line by line
                local rendered_file="${temp_dir}/rendered_${i}.txt"
                viu -w "$img_width" -h "$img_height" "$image_file" 2>/dev/null > "$rendered_file"
                # Sanitize VIU output: remove cursor movement codes but keep colors
                if command -v perl &> /dev/null; then
                    perl -i -pe "s/\x1b\[[0-9;]*[A-HJKSTf]//g" "$rendered_file" 2>/dev/null
                fi
                if [ $? -eq 0 ] && [ -s "$rendered_file" ]; then
                    image_line_files[$i]="$rendered_file"
                    has_image[$i]=1
                else
                    rm -f "$rendered_file" 2>/dev/null
                fi
            fi
        fi
    done
    
    # Pass 3: Draw images row by row (offline rendering)
    # For each row (0 to img_height-1), draw that row for all columns
    for ((row=0; row<img_height; row++)); do
        for i in "${!items[@]}"; do
            local x_pos="${col_positions[$i]}"
            local current_y=$((start_row + row + 1))
            
            if [[ "${has_image[$i]}" -eq 1 ]]; then
                if [[ "${is_kitty[$i]}" -eq 1 ]]; then
                    # For kitty, render once on first row only
                    if [[ "$row" -eq 0 ]]; then
                        local image_file="${image_files[$i]}"
                        kitty +kitten icat --align left --place "${img_width}x${img_height}@${x_pos}x$((start_row + 1))" "$image_file" 2>/dev/null
                    fi
                else
                    # For viu: Read specific row from pre-rendered file and draw at correct position
                    local rendered_file="${image_line_files[$i]}"
                    if [[ -n "$rendered_file" ]] && [[ -f "$rendered_file" ]]; then
                        # Move cursor to exact position for this row and column
                        tput cup "$current_y" "$x_pos"
                        # Read and output the specific line (row+1 because sed line numbers start at 1)
                        local image_line
                        image_line=$(sed -n "$((row + 1))p" "$rendered_file" 2>/dev/null)
                        if [[ -n "$image_line" ]]; then
                            # Remove trailing newline and any remaining escape codes
                            local clean_line="${image_line%$'\n'}"
                            # Remove any cursor movement codes that might have leaked through
                            clean_line=$(echo -n "$clean_line" | sed 's/\x1b\[[0-9;]*[A-HJKSTf]//g' | sed 's/\[0m//g')
                            # Output the line - viu should already respect width
                            printf "%s" "$clean_line"
                            # Position cursor at end of image area (x_pos + img_width) to prevent overwrite
                            # This ensures next column starts at correct position
                            local end_x=$((x_pos + img_width))
                            local term_cols=$(tput cols)
                            if [ "$end_x" -gt "$term_cols" ]; then
                                end_x=$term_cols
                            fi
                            tput cup "$current_y" "$end_x"
                        fi
                    fi
                fi
            else
                # Draw placeholder box row by row (always draw if no image)
                tput cup "$current_y" "$x_pos"
                if [[ "$row" -eq 0 ]]; then
                    echo -ne "${CYAN}┌──────────────────┐${RESET}"
                elif [[ "$row" -eq $((img_height-1)) ]]; then
                    echo -ne "${CYAN}└──────────────────┘${RESET}"
                elif [[ "$row" -eq 7 ]]; then
                    # Center row - show "No Poster" text
                    echo -ne "${CYAN}│${RESET}"
                    tput cup "$current_y" $((x_pos + 5))
                    echo -ne "${CYAN}No Poster${RESET}"
                    tput cup "$current_y" $((x_pos + 19))
                    echo -ne "${CYAN}│${RESET}"
                else
                    echo -ne "${CYAN}│                  │${RESET}"
                fi
                # Ensure cursor is positioned after placeholder
                tput cup "$current_y" $((x_pos + 20))
            fi
        done
        # CRITICAL: After drawing each image row, don't move cursor - let it stay at end of row
        # We'll position it correctly before drawing text
    done
    
    # CRITICAL: After drawing all images, ensure cursor is positioned correctly
    # Images occupy rows: start_row+1 to start_row+img_height (15 lines)
    # Text should start at: start_row + img_height + 1
    # Don't move cursor here - we'll position it per-item when drawing text
    
    # Pass 4: Draw all text below images
    # Calculate text starting row (below images with 1 line spacing for compact layout)
    # Images are drawn from start_row+1 to start_row+img_height (15 lines)
    # Add 1 line spacing, so text starts at start_row + 16
    # CRITICAL: text_row must always be relative to start_row, not adjusted by scrolling
    local text_row=$((start_row + img_height + 1))
    local term_cols=$(tput cols)
    local term_lines_check=$(tput lines)
    
    # CRITICAL: Ensure text_row is within terminal bounds
    if [ "$text_row" -ge "$term_lines_check" ] || [ "$text_row" -lt 1 ]; then
        # If text row is beyond terminal, adjust it
        text_row=$((term_lines_check - 5))
        if [ "$text_row" -lt 1 ]; then
            text_row=1
        fi
    fi
    
    # CRITICAL: Ensure text_row is at least below the image area
    local image_end_row=$((start_row + img_height))
    if [ "$text_row" -le "$image_end_row" ]; then
        text_row=$((image_end_row + 1))
    fi
    
    # Draw text for each item completely before moving to next
    # This prevents overwrites from cursor positioning
    for i in "${!items[@]}"; do
        local item="${items[$i]}"
        local x_pos="${col_positions[$i]}"
        IFS='|' read -r source name magnet quality size extra poster_url <<< "$item"
        
        local item_num=$((start_index + i + 1))
        
        # Check if item is COMBINED
        local is_combined=false
        local combined_sources=()
        local combined_seeds=()
        local combined_qualities=()
        local combined_sizes=()
        local max_seeds=0
        local source_tags=""
        
        if [[ "$source" == "COMBINED" ]]; then
            is_combined=true
            # Parse COMBINED format: COMBINED|Name|Sources|Seeds|Qualities|Sizes|Magnets|Poster
            IFS='|' read -r _ c_name c_sources c_seeds c_qualities c_sizes c_magnets c_poster <<< "$item"
            name="$c_name"
            poster_url="$c_poster"
            
            # Split arrays by ^ delimiter
            IFS='^' read -ra combined_sources <<< "$c_sources"
            IFS='^' read -ra combined_seeds <<< "$c_seeds"
            IFS='^' read -ra combined_qualities <<< "$c_qualities"
            IFS='^' read -ra combined_sizes <<< "$c_sizes"
            
            # Build source tags (e.g., [TPB] [YTS]) - deduplicate sources
            declare -A seen_sources=()
            for src in "${combined_sources[@]}"; do
                # Skip if we've already seen this source
                if [[ -n "${seen_sources[$src]}" ]]; then
                    continue
                fi
                seen_sources[$src]=1
                case "$src" in
                    YTS) source_tags="${source_tags}[${GREEN}YTS${RESET}] " ;;
                    TPB) source_tags="${source_tags}[${YELLOW}TPB${RESET}] " ;;
                    EZTV) source_tags="${source_tags}[${BLUE}EZTV${RESET}] " ;;
                    1337x) source_tags="${source_tags}[${MAGENTA}1337x${RESET}] " ;;
                    *) source_tags="${source_tags}[${CYAN}${src}${RESET}] " ;;
                esac
            done
            unset seen_sources
            source_tags=$(echo "$source_tags" | sed 's/[[:space:]]*$//')  # Trim trailing space
            
            # Calculate max seeds
            for seed_str in "${combined_seeds[@]}"; do
                local seed_val=$(echo "$seed_str" | grep -oE '[0-9]+' | head -1)
                if [ -n "$seed_val" ] && [ "$seed_val" -gt "$max_seeds" ] 2>/dev/null; then
                    max_seeds=$seed_val
                fi
            done
            
            # Use best quality (prefer 1080p, then 720p, then first available)
            quality=""
            for q in "${combined_qualities[@]}"; do
                if [[ "$q" =~ 1080 ]]; then
                    quality="1080p"
                    break
                elif [[ "$q" =~ 720 ]] && [ -z "$quality" ]; then
                    quality="720p"
                elif [ -z "$quality" ] && [ -n "$q" ] && [ "$q" != "N/A" ]; then
                    quality="$q"
                fi
            done
            if [ -z "$quality" ]; then
                quality="N/A"
            fi
            
            # Use first size as representative
            if [ ${#combined_sizes[@]} -gt 0 ]; then
                size="${combined_sizes[0]}"
            fi
            
            # Set seeds for display
            if [ "$max_seeds" -gt 0 ]; then
                seeds="$max_seeds"
            else
                seeds=""
            fi
        else
            # Regular item - use existing logic
            local source_color="$CYAN"
            case "$source" in
                YTS) source_color="$GREEN" ;;
                TPB) source_color="$YELLOW" ;;
                EZTV) source_color="$BLUE" ;;
                1337x) source_color="$MAGENTA" ;;
            esac
        fi
        
        local display_name="${name:0:38}"
        if [ "${#name}" -gt 38 ]; then
            display_name="${display_name}..."
        fi
        
        # Calculate available width for this column (needed for both row 2 and row 3)
        local next_x
        if [ "$i" -lt $((${#items[@]} - 1)) ]; then
            next_x="${col_positions[$((i + 1))]}"
        else
            next_x=$term_cols
        fi
        local col_width=$((next_x - x_pos - 1))  # Leave 1 char margin
        if [ "$col_width" -gt 35 ]; then col_width=35; fi
        if [ "$col_width" -lt 20 ]; then col_width=20; fi
        
        # Write all three lines of text for this item at once
        # CRITICAL: Calculate text_row relative to start_row (where images were drawn)
        # Images are drawn from start_row+1 to start_row+img_height (15 lines)
        # Text should start at start_row + img_height + 1 (row 16 from start_row)
        local image_end_row=$((start_row + img_height))
        local actual_text_row=$((image_end_row + 1))
        
        # CRITICAL: Ensure text_row is below image area first
        if [ "$actual_text_row" -le "$image_end_row" ]; then
            actual_text_row=$((image_end_row + 1))
        fi
        
        # CRITICAL: Then check if it's within terminal bounds
        # If beyond terminal, we still need to draw it, but it might scroll
        # Don't skip drawing - let the terminal handle scrolling
        if [ "$actual_text_row" -lt 1 ]; then
            actual_text_row=1
        fi
        
        # CRITICAL: Clear each line before writing to prevent overlap
        # Calculate clear end position
        local clear_end
        if [ "$i" -lt $((${#items[@]} - 1)) ]; then
            clear_end="${col_positions[$((i + 1))]}"
        else
            clear_end=$term_cols
        fi
        
        # CRITICAL: Strip ANSI codes from quality and extra fields first before parsing
        local clean_quality=$(echo -n "$quality" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\[0m//g')
        local clean_extra=$(echo -n "$extra" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\[0m//g')
        
        # Extract seeds from either quality field (TPB format: "1234 seeds") or extra field (YTSRS format: "1234 seeds, 567 peers")
        # Skip extraction for COMBINED entries (seeds already set)
        local quality_has_seeds=false
        if [ "$is_combined" != true ]; then
            seeds=""
            if [[ "$clean_quality" =~ ([0-9]+)[[:space:]]*seeds ]]; then
                seeds="${BASH_REMATCH[1]}"
                quality_has_seeds=true
            elif [[ "$clean_extra" =~ ([0-9]+)[[:space:]]*seeds ]]; then
                seeds="${BASH_REMATCH[1]}"
            fi
        fi
        
        # Get quality preference from config (default: 1080p)
        local config_file=$(get_termflix_config_file)
        local preferred_quality="1080p"
        if [ -f "$config_file" ]; then
            local config_quality=$(grep "^QUALITY=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]')
            if [ -n "$config_quality" ]; then
                preferred_quality="$config_quality"
            fi
        fi
        
        # Extract quality (720p/1080p) - use config preference as default
        local quality_display="$preferred_quality"
        if [ -n "$clean_quality" ] && [ "$clean_quality" != "N/A" ] && [ "$quality_has_seeds" = false ]; then
            # Extract resolution from quality string (e.g., "720p", "1080p", "4K")
            if [[ "$clean_quality" =~ ([0-9]+[pK]) ]]; then
                quality_display="${BASH_REMATCH[1]}"
            elif [[ "$clean_quality" =~ (720|1080|2160|4K) ]]; then
                if [[ "$clean_quality" =~ 720 ]]; then
                    quality_display="720p"
                elif [[ "$clean_quality" =~ 1080 ]]; then
                    quality_display="1080p"
                elif [[ "$clean_quality" =~ (2160|4K) ]]; then
                    quality_display="4K"
                fi
            fi
        fi
        
        # Get IMDB rating and genre from TMDB API cache
        local imdb_rating=""
        local rating_display=""
        local genre_display=""
        if [ -n "$name" ]; then
            # Extract year from name if available
            local year=$(echo "$name" | grep -oE '[0-9]{4}' | head -1)
            local clean_title=$(echo "$name" | sed -E 's/\./ /g' | sed -E 's/ \([0-9]{4}\).*//' | sed 's/\[.*\]//g' | xargs)
            
            # Check cache for rating and genre (using TMDB cache)
            local cache_dir=$(get_termflix_cache_dir)/tmdb
            local cache_key=$(echo "${clean_title}_${year}" | tr -cd '[:alnum:]')
            local cache_file="$cache_dir/${cache_key}.json"
            
            if [ -f "$cache_file" ]; then
                # Try to get rating from cached file
                if command -v jq &> /dev/null; then
                    imdb_rating=$(cat "$cache_file" 2>/dev/null | jq -r '.imdbRating // .vote_average // empty' 2>/dev/null)
                    # Get first genre from genres array
                    genre_display=$(cat "$cache_file" 2>/dev/null | jq -r '.genres[0].name // .genres[0] // empty' 2>/dev/null)
                else
                    imdb_rating=$(cat "$cache_file" 2>/dev/null | grep -o '"imdbRating":"[^"]*"' | cut -d'"' -f4)
                    if [ -z "$imdb_rating" ]; then
                        imdb_rating=$(cat "$cache_file" 2>/dev/null | grep -o '"vote_average":[0-9.]*' | cut -d':' -f2)
                    fi
                    # Try to get genre (first one)
                    genre_display=$(cat "$cache_file" 2>/dev/null | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
                fi
            fi
            
            # Format rating display (e.g., "7.5 ⭐")
            if [ -n "$imdb_rating" ] && [ "$imdb_rating" != "N/A" ] && [ "$imdb_rating" != "" ] && [ "$imdb_rating" != "null" ]; then
                # Round to 1 decimal place
                local rating_num=$(echo "$imdb_rating" | awk '{printf "%.1f", $1}')
                rating_display="${rating_num} ⭐"
            fi
        fi
        
        # Clean up title for display (remove dots, brackets, etc.)
        local clean_display_name=$(echo "$display_name" | sed -E 's/\./ /g' | sed -E 's/\[.*\]//g' | sed -E 's/  +/ /g' | xargs)
        # Truncate title if too long (leave some room for column width)
        local title_max_len=$((col_width - 5))
        if [ "$title_max_len" -lt 10 ]; then
            title_max_len=10
        fi
        if [ "${#clean_display_name}" -gt "$title_max_len" ]; then
            clean_display_name="${clean_display_name:0:$title_max_len}..."
        fi
        
        # Row 1: [Number] [Source] Quality | Rating ⭐
        if [ "$actual_text_row" -ge 1 ]; then
            tput cup "$actual_text_row" "$x_pos"
            # Clear to end of column
            printf "%*s" $((clear_end - x_pos)) ""
            tput cup "$actual_text_row" "$x_pos"
            local row1_text=""
            if [ "$is_combined" = true ]; then
                # For COMBINED entries, show multiple source tags
                row1_text="${BOLD}[${item_num}]${RESET} ${source_tags} ${CYAN}${quality_display}${RESET}"
            else
                # For regular entries, show single source
                row1_text="${BOLD}[${item_num}]${RESET} ${source_color}[${source}]${RESET} ${CYAN}${quality_display}${RESET}"
            fi
            if [ -n "$rating_display" ]; then
                row1_text="${row1_text} | ${rating_display}"
            fi
            echo -ne "$row1_text"
        fi
        
        # Row 2: Full Title (cleaned up)
        local text_row_2=$((actual_text_row + 1))
        if [ "$text_row_2" -ge 1 ]; then
            tput cup "$text_row_2" "$x_pos"
            # Clear to end of column
            printf "%*s" $((clear_end - x_pos)) ""
            tput cup "$text_row_2" "$x_pos"
            echo -ne "${BOLD}${clean_display_name}${RESET}"
        fi
        
        # Row 3: Seeds | Genre
        local text_row_3=$((actual_text_row + 2))
        if [ "$text_row_3" -ge 1 ]; then
            tput cup "$text_row_3" "$x_pos"
            # Clear to end of column
            printf "%*s" $((clear_end - x_pos)) ""
            tput cup "$text_row_3" "$x_pos"
            local row3_text=""
            if [ -n "$seeds" ]; then
                row3_text="${YELLOW}${seeds} Seeds${RESET}"
            fi
            if [ -n "$genre_display" ] && [ "$genre_display" != "" ] && [ "$genre_display" != "null" ]; then
                if [ -n "$row3_text" ]; then
                    row3_text="${row3_text} | "
                fi
                row3_text="${row3_text}[${genre_display}]"
            fi
            echo -ne "$row3_text"
            
            # After writing all text for this item, move cursor to end of its column area
            # This prevents overwrites when we write the next column
            tput cup "$text_row_3" $((clear_end - 1))
        fi
    done
    
    # Cleanup rendered files
    for rendered_file in "${image_line_files[@]}"; do
        [[ -n "$rendered_file" ]] && rm -f "$rendered_file" 2>/dev/null
    done
    
    # Calculate the next row position
    # Layout: start_row + img_height (15) + spacing (1) + text_lines (3) = start_row + 19
    # But we use row_height=21 for consistency with scrolling logic (3 text lines)
    local next_row=$((start_row + row_height))
    
    # Ensure cursor is positioned at the next row before returning
    # This ensures the cursor is in a known state for the next row
    tput cup "$next_row" 0
    
    # Return the next row position via stderr (so it doesn't mix with stdout output)
    echo "$next_row" >&2
}

# Helper function to redraw a specific page from cached results
# This function displays a page without re-fetching data
redraw_catalog_page() {
    local title="$1"
    local cached_results_ref="$2"  # Name of array variable containing cached results
    local page="$3"
    local per_page="$4"
    local total="$5"
    
    # Get the cached results array
    eval "local all_results=(\"\${${cached_results_ref}[@]}\")"
    
    # Check if results are already grouped (contain COMBINED entries)
    # If not, group them to remove duplicates
    local needs_grouping=true
    for result in "${all_results[@]}"; do
        IFS='|' read -r result_source _ <<< "$result"
        if [[ "$result_source" == "COMBINED" ]]; then
            needs_grouping=false
            break
        fi
    done
    
    # Group results to remove duplicates (only if not already grouped)
    if [ "$needs_grouping" = true ] && [ ${#all_results[@]} -gt 0 ]; then
        local grouped_results=()
        # Create temp file for grouping
        local group_input=$(mktemp)
        printf "%s\n" "${all_results[@]}" > "$group_input"
        
        # Run grouping
        local group_output=$(cat "$group_input" | group_results 2>/dev/null)
        
        # Read back into array
        if [ -n "$group_output" ]; then
             while IFS= read -r line || [ -n "$line" ]; do
                 grouped_results+=("$line")
             done <<< "$group_output"
             all_results=("${grouped_results[@]}")
             total=${#all_results[@]}
        fi
        rm -f "$group_input"
    fi
    
    # Calculate pagination
    local total_pages=$(( (total + per_page - 1) / per_page ))
    if [ "$total_pages" -eq 0 ]; then total_pages=1; fi
    local start_idx=$(( (page - 1) * per_page ))
    local end_idx=$(( start_idx + per_page ))
    
    # Clear screen and redraw
    clear
    echo -e "${BOLD}${YELLOW}$title${RESET}\n"
    
    # Display pagination info
    echo -e "${BOLD}${GREEN}Found ${total} results${RESET} (Page ${page}/${total_pages})"
    
    # Check if we have any results with posters
    local has_posters=false
    for result in "${all_results[@]}"; do
        IFS='|' read -r result_source result_name result_magnet result_quality result_size result_extra result_poster <<< "$result"
        
        # Handle COMBINED entries
        if [[ "$result_source" == "COMBINED" ]]; then
            # COMBINED|Name|Sources|Seeds|Qualities|Sizes|Magnets|Poster
            IFS='|' read -r _ _ _ _ _ _ _ result_poster <<< "$result"
        fi
        
        if [[ -n "$result_poster" ]] && [[ "$result_poster" != "N/A" ]]; then
            has_posters=true
            break
        fi
    done
    
    # Show note about posters
    if [ "$has_posters" = false ] && check_viu >/dev/null 2>&1; then
        echo -e "${YELLOW}Note:${RESET} Movie posters are not available for these results."
    elif [ "$has_posters" = true ] && ! check_viu >/dev/null 2>&1; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo -e "${YELLOW}Note:${RESET} Install ${CYAN}viu${RESET} to see movie posters: ${CYAN}brew install viu${RESET} or ${CYAN}cargo install viu${RESET}"
        else
            echo -e "${YELLOW}Note:${RESET} Install ${CYAN}viu${RESET} to see movie posters: ${CYAN}cargo install viu${RESET}"
        fi
    fi
    echo
    
    # Display results in grid layout (same logic as before)
    local term_cols=$(tput cols)
    local num_cols=$((term_cols / 40))
    if [ "$num_cols" -lt 1 ]; then num_cols=1; fi
    if [ "$num_cols" -gt 5 ]; then num_cols=5; fi
    
    local index=$start_idx
    local current_start_row=5
    local term_lines=$(tput lines)
    local term_cols=$(tput cols)
    local row_height=21  # Must match row_height in draw_grid_row function
    local scroll_offset=0  # Track how much we've scrolled (for cursor position calculations)
    
    local row_items=()
    local row_count=0
    
    tput cup "$current_start_row" 0
    echo
    
    while [ $index -lt $end_idx ] && [ $index -lt $total ]; do
        local result="${all_results[$index]}"
        
        if [ -z "$result" ]; then
            index=$((index + 1))
            continue
        fi
        
        row_items+=("$result")
        row_count=$((row_count + 1))
        
        if [ $row_count -eq $num_cols ] || [ $index -eq $((end_idx - 1)) ] || [ $index -eq $((total - 1)) ]; then
            # Parallel Fetching of Posters (same as before)
            local pids=()
            local temp_files=()
            local fetch_indices=()
            local fetching=false
            
            for i in "${!row_items[@]}"; do
                local item="${row_items[$i]}"
                IFS='|' read -r source name magnet quality size extra poster_url <<< "$item"
                
                # Check if item is COMBINED
                if [[ "$source" == "COMBINED" ]]; then
                    # Parse COMBINED format: COMBINED|Name|Sources|Seeds|Qualities|Sizes|Magnets|Poster
                    IFS='|' read -r _ c_name _ _ _ _ _ c_poster <<< "$item"
                    name="$c_name"
                    poster_url="$c_poster"
                fi
                
                local title_year=$(echo "$name" | sed -E 's/\./ /g')
                local year=$(echo "$title_year" | grep -oE '\(?[0-9]{4}\)?' | head -1 | tr -d '()')
                
                # Careful title cleaning: remove year and everything after, remove brackets
                local title_clean1=$(echo "$title_year" | sed -E "s/\\(${year}\\).*//")
                local title_clean2=$(echo "$title_clean1" | sed -E "s/ ${year}.*//")
                local clean_title=$(echo "$title_clean2" | sed 's/\[.*\]//g' | xargs)
                
                if [[ -z "$poster_url" ]] || [[ "$poster_url" == "N/A" ]]; then
                    if [ -n "$clean_title" ]; then
                        fetching=true
                        local temp_file=$(mktemp)
                        temp_files[$i]="$temp_file"
                        fetch_indices+=($i)
                        (
                            local new_poster=$(fetch_tmdb_poster "$clean_title" "$year")
                            echo "$new_poster" > "$temp_file"
                        ) &
                        pids+=($!)
                    fi
                else
                    local cache_dir=$(get_termflix_cache_dir)/tmdb
                    local cache_key=$(echo "${clean_title}_${year}" | tr -cd '[:alnum:]')
                    local cache_file="$cache_dir/${cache_key}.json"
                    
                    if [ ! -f "$cache_file" ] && [ -n "$clean_title" ]; then
                        (
                            fetch_tmdb_poster "$clean_title" "$year" > /dev/null 2>&1
                        ) &
                        pids+=($!)
                    fi
                fi
            done
            
            if [ "$fetching" = true ]; then
                tput sc
                echo -ne "${YELLOW}Fetching posters...${RESET}"
                for pid in "${pids[@]}"; do
                    wait "$pid" 2>/dev/null
                done
                tput rc
                tput el
                
                for i in "${fetch_indices[@]}"; do
                    local temp_file="${temp_files[$i]}"
                    if [ -f "$temp_file" ]; then
                        local new_poster=$(cat "$temp_file")
                        rm -f "$temp_file"
                        if [ -n "$new_poster" ] && [ "$new_poster" != "N/A" ]; then
                            local item="${row_items[$i]}"
                            IFS='|' read -r source name magnet quality size extra old_poster <<< "$item"
                            
                            # Handle COMBINED entries - preserve the COMBINED format
                            if [[ "$source" == "COMBINED" ]]; then
                                # COMBINED|Name|Sources|Seeds|Qualities|Sizes|Magnets|Poster
                                IFS='|' read -r _ c_name c_sources c_seeds c_qualities c_sizes c_magnets _ <<< "$item"
                                row_items[$i]="COMBINED|$c_name|$c_sources|$c_seeds|$c_qualities|$c_sizes|$c_magnets|$new_poster"
                            else
                                row_items[$i]="$source|$name|$magnet|$quality|$size|$extra|$new_poster"
                            fi
                        fi

                    fi
                done
            fi
            
            # Position cursor at current_start_row for this row
            # For first row, this is the initial position (5)
            # For subsequent rows, this is where the previous row ended (next_row from draw_grid_row)
            # This creates a chain: row1 ends at next_row -> row2 starts at next_row -> row2 ends at next_row2 -> etc.
            
            if [ "$current_start_row" -lt 1 ]; then
                current_start_row=1
            fi
            
            # SIMPLIFIED APPROACH: Check if we're getting close to bottom, scroll if needed
            # When cursor approaches bottom (within 23 lines), scroll up and recalculate position
            local available_lines=$((term_lines - current_start_row))
            local scroll_threshold=23  # Scroll when we're within 23 lines of bottom
            
            # If we're getting close to the bottom, scroll up to make room
            if [ "$available_lines" -lt "$scroll_threshold" ] || [ "$current_start_row" -ge "$term_lines" ]; then
                # Scroll by outputting newlines - this moves visible content up
                # Scroll enough to ensure we have room for the row (row_height = 21) plus margin
                local scroll_amount=$((row_height + 8))  # Scroll row_height + 8 lines for safety
                
                # Output newlines to scroll the terminal up
                for ((scroll=0; scroll<scroll_amount; scroll++)); do
                    echo
                done
                
                # After scrolling, recalculate where we should start drawing
                # We want to start at a position that gives us enough room for the row
                # Calculate from terminal height: leave row_height + 10 lines of space (further reduced gap)
                local new_start_row=$((term_lines - row_height - 10))
                if [ "$new_start_row" -lt 1 ]; then
                    new_start_row=1
                fi
                
                # Update current_start_row to the new calculated position
                current_start_row=$new_start_row
                
                # Position cursor at the new start row
                tput cup "$current_start_row" 0
            else
                # We have enough space, just position cursor at current_start_row
                tput cup "$current_start_row" 0
            fi
            
            local item_start_index=$((index - row_count + 1))
            if [ "$item_start_index" -lt 0 ]; then
                item_start_index=0
            fi
            
            # Draw the row - this function will position the cursor at next_row when done
            local temp_return=$(mktemp)
            draw_grid_row "$current_start_row" "$item_start_index" "$num_cols" "${row_items[@]}" 2>"$temp_return"
            local next_row
            next_row=$(tail -1 "$temp_return" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
            rm -f "$temp_return"
            
            # Fallback if next_row wasn't returned correctly
            if ! [[ "$next_row" =~ ^[0-9]+$ ]] || [ -z "$next_row" ]; then
                next_row=$((current_start_row + row_height))
            fi
            
            # CRITICAL: Use next_row as the starting point for the next row
            # draw_grid_row already positioned the cursor at next_row, so we just update
            # current_start_row to use for the next iteration. This creates a chain where
            # each row starts exactly where the previous row ended.
            # 
            # Note: If we scrolled before drawing this row, we already adjusted current_start_row,
            # and draw_grid_row calculated next_row from that adjusted position, so next_row
            # should already be correct relative to the scrolled screen.
            current_start_row=$next_row
            
            # draw_grid_row already positioned cursor at (next_row, 0), so we're ready
            # for the next iteration. The scroll check at the start of next iteration will
            # handle scrolling if needed.
            
            row_items=()
            row_count=0
        fi
        index=$((index + 1))
    done
    
    # After drawing all rows, current_start_row contains where the last row ended
    # draw_grid_row already positioned the cursor at current_start_row (which is next_row from last draw)
    # Add a couple of blank lines for spacing before navigation
    echo
    echo
    # Cursor is now positioned correctly for navigation text to be displayed
}

# Display catalog results in columns with pagination
display_catalog() {
    local title="$1"
    local all_results=()
    local page="${CATALOG_PAGE:-1}"
    local per_page=20
    shift
    
    # Store original arguments for pagination navigation
    local original_args=("$@")
    
    echo -e "${BOLD}${YELLOW}$title${RESET}\n"
    
    # Initialize termflix directories
    init_termflix_dirs
    
    # Generate cache key from function names and arguments
    local cache_key=$(generate_cache_key "$title" "${original_args[@]}")
    local cache_dir=$(get_termflix_cache_dir)
    local cache_file="$cache_dir/catalog_${cache_key}.txt"
    
    # Check if cache is valid (less than 1 hour old)
    # Also invalidate if cache contains legacy "YTSRS" sources (we now use "YTS")
    # or if result count is suspicious (999 usually implies cache error)
    if [ -f "$cache_file" ] && (grep -q "YTSRS" "$cache_file" || grep -q "No Poster" "$cache_file"); then
         rm -f "$cache_file"
    fi

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
        
        # Enrich entries with missing posters from TMDB
        if [ ${#all_results[@]} -gt 0 ]; then
            printf "${CYAN}Fetching posters from TMDB...${RESET}"
            enrich_missing_posters all_results 20  # Enrich up to 20 entries per page
            printf "\r${GREEN}✓ Enriched posters${RESET}                    \n"
        fi
        
        # Save GROUPED results to cache (after grouping and enrichment)
        if [ ${#all_results[@]} -gt 0 ]; then
            printf "%s\n" "${all_results[@]}" > "$cache_file" 2>/dev/null
        fi
    fi
    
    # Calculate pagination
    local total="${#all_results[@]}"
    local total_pages=$(( (total + per_page - 1) / per_page ))
    
    # Store cached results in a variable name for redraw function
    local cached_results_var="cached_results_$$"
    eval "declare -a ${cached_results_var}=()"
    for result in "${all_results[@]}"; do
        eval "${cached_results_var}+=(\"\$result\")"
    done
    
    # Display initial page using redraw function
    redraw_catalog_page "$title" "$cached_results_var" "$page" "$per_page" "$total"
    
    # Interactive selection with pagination using keypress detection
    if [ -t 0 ]; then
        
        # Navigation loop with keypress detection
        local current_page=$page
        local selection=""
        local number_input=""
        
        while true; do
            # Display navigation instructions right after the last row
            # redraw_catalog_page already positioned the cursor correctly (after last row + 2 blank lines)
            # So we can just display navigation directly - no need to reposition cursor
            
            if [ $total_pages -gt 1 ]; then
                echo -e "${CYAN}Navigation:${RESET}"
                echo -e "  ${GREEN}n${RESET} - Next page (press key, no Enter needed)"
                echo -e "  ${GREEN}p${RESET} - Previous page (press key, no Enter needed)"
                echo -e "  ${GREEN}1-${total}${RESET} - Select torrent (type number, press Enter)"
                echo -e "  ${GREEN}q${RESET} or ${GREEN}Esc${RESET} - Cancel/Quit"
                echo
            else
                echo -e "${CYAN}Navigation:${RESET}"
                echo -e "  ${GREEN}1-${total}${RESET} - Select torrent (type number, press Enter)"
                echo -e "  ${GREEN}q${RESET} or ${GREEN}Esc${RESET} - Cancel/Quit"
                echo
            fi
            
            # Setup terminal for keypress detection
            local old_stty
            old_stty=$(stty -g 2>/dev/null) || true
            stty -icanon -echo 2>/dev/null || true
            
            # Read a single keypress
            local key
            if IFS= read -rsn1 key 2>/dev/null; then
                # Handle escape sequences (arrow keys, etc.)
                if [ "$key" = $'\033' ]; then
                    read -rsn1 -t 0.1 key 2>/dev/null || true
                    if [ "$key" = "[" ]; then
                        read -rsn1 -t 0.1 key 2>/dev/null || true
                        # Arrow keys - ignore for now, could add later
                    else
                        # ESC key - cancel
                        key="q"
                    fi
                fi
            else
                # No input or error
                key=""
            fi
            
            # Restore terminal settings
            [ -n "$old_stty" ] && stty "$old_stty" 2>/dev/null || true
            
            # Handle keypress
            case "$key" in
                n|N)
                    if [ $current_page -lt $total_pages ]; then
                        current_page=$((current_page + 1))
                        # Redraw page from cache (no re-fetch)
                        redraw_catalog_page "$title" "$cached_results_var" "$current_page" "$per_page" "$total"
                        continue
                    else
                        echo -e "${YELLOW}Already on last page.${RESET}"
                        sleep 0.5
                        # Redraw to clear message
                        redraw_catalog_page "$title" "$cached_results_var" "$current_page" "$per_page" "$total"
                    fi
                    ;;
                p|P)
                    if [ $current_page -gt 1 ]; then
                        current_page=$((current_page - 1))
                        # Redraw page from cache (no re-fetch)
                        redraw_catalog_page "$title" "$cached_results_var" "$current_page" "$per_page" "$total"
                        continue
                    else
                        echo -e "${YELLOW}Already on first page.${RESET}"
                        sleep 0.5
                        # Redraw to clear message
                        redraw_catalog_page "$title" "$cached_results_var" "$current_page" "$per_page" "$total"
                    fi
                    ;;
                q|Q|$'\033')
                    echo "Cancelled."
                    unset CATALOG_PAGE
                    cleanup_posters
                    return
                    ;;
                [0-9])
                    # Start collecting number input
                    number_input="$key"
                    # Read remaining digits (if any) with normal input mode
                    local old_stty2
                    old_stty2=$(stty -g 2>/dev/null) || true
                    stty icanon echo 2>/dev/null || true
                    echo -ne "${YELLOW}Enter selection: ${number_input}${RESET}"
                    while IFS= read -rsn1 -t 1 key2 2>/dev/null; do
                        if [[ "$key2" =~ [0-9] ]]; then
                            number_input="${number_input}${key2}"
                            echo -ne "$key2"
                        elif [ "$key2" = "" ] || [ "$key2" = $'\n' ] || [ "$key2" = $'\r' ]; then
                            # Enter pressed
                            break
                        elif [ "$key2" = $'\177' ] || [ "$key2" = $'\b' ]; then
                            # Backspace
                            if [ ${#number_input} -gt 1 ]; then
                                number_input="${number_input%?}"
                                echo -ne "\b \b"
                            fi
                        else
                            break
                        fi
                    done
                    [ -n "$old_stty2" ] && stty "$old_stty2" 2>/dev/null || true
                    echo
                    
                    selection="$number_input"
                    number_input=""
                    ;;
                *)
                    # Ignore other keys
                    continue
                    ;;
            esac
            
            # Handle numeric selection
            if [ -n "$selection" ] && [[ "$selection" =~ ^[0-9]+$ ]]; then
                if [ "$selection" -ge 1 ] && [ "$selection" -le "$total" ] 2>/dev/null; then
                    local selected_result
                    eval "selected_result=\"\${${cached_results_var}[$((selection - 1))]}\""

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
                        
                        # Build torrent list for sidebar picker
                        # Format: source|quality|seeds|size|magnet
                        local -a torrent_options=()
                        for i in "${!sources_arr[@]}"; do
                            local src="${sources_arr[$i]}"
                            local qty="${qualities_arr[$i]}"
                            local sz="${sizes_arr[$i]}"
                            local sd="${seeds_arr[$i]}"
                            local mg="${magnets_arr[$i]}"
                            torrent_options+=("${src}|${qty}|${sd}|${sz}|${mg}")
                        done
                        
                        # Get poster path if available
                        local poster_file=""
                        if [[ -n "$c_poster" ]] && [[ "$c_poster" != "N/A" ]]; then
                            # Download poster to temp file for display
                            local temp_poster="${TMPDIR:-/tmp}/termflix_poster_$$.jpg"
                            curl -s --max-time 5 "$c_poster" -o "$temp_poster" 2>/dev/null
                            [[ -f "$temp_poster" ]] && poster_file="$temp_poster"
                        fi
                        
                        # Use Stremio-style sidebar picker
                        local choice_idx=""
                        local picker_result
                        if picker_result=$(show_sidebar_picker "$c_name" "$poster_file" "${torrent_options[@]}" 2>/dev/null); then
                            # Strip any non-numeric characters and get just the index
                            choice_idx=$(echo "$picker_result" | tr -cd '0-9' | head -c 10)
                            
                            # Validate the index
                            if [[ -n "$choice_idx" ]] && [[ "$choice_idx" =~ ^[0-9]+$ ]] && \
                               [[ $choice_idx -ge 0 ]] && [[ $choice_idx -lt ${#sources_arr[@]} ]]; then
                                # User selected a valid option
                                source="${sources_arr[$choice_idx]}"
                                magnet="${magnets_arr[$choice_idx]}"
                                quality="${qualities_arr[$choice_idx]}"
                                size="${sizes_arr[$choice_idx]}"
                                name="$c_name"
                                
                                # Clean up temp poster
                                [[ -n "$poster_file" ]] && rm -f "$poster_file" 2>/dev/null
                            else
                                # Invalid index - treat as cancel
                                [[ -n "$poster_file" ]] && rm -f "$poster_file" 2>/dev/null
                                selection=""
                                redraw_catalog_page "$title" "$cached_results_var" "$current_page" "$per_page" "$total"
                                continue
                            fi
                        else
                            # User cancelled or picker failed
                            [[ -n "$poster_file" ]] && rm -f "$poster_file" 2>/dev/null
                            selection=""
                            redraw_catalog_page "$title" "$cached_results_var" "$current_page" "$per_page" "$total"
                            continue
                        fi
                    else
                        # Single source entry - also show sidebar picker with single option
                        # Build single torrent option
                        local -a torrent_options=()
                        # Parse: source|name|magnet|quality|size|extra|poster_url
                        local seeds="N/A"
                        if [[ -n "$extra" ]] && [[ "$extra" =~ [0-9]+ ]]; then
                            seeds="$extra"
                        fi
                        torrent_options+=("${source}|${quality}|${seeds}|${size}|${magnet}")
                        
                        # Get poster path if available
                        local poster_file=""
                        if [[ -n "$poster_url" ]] && [[ "$poster_url" != "N/A" ]]; then
                            local temp_poster="${TMPDIR:-/tmp}/termflix_poster_$$.jpg"
                            curl -s --max-time 5 "$poster_url" -o "$temp_poster" 2>/dev/null
                            [[ -f "$temp_poster" ]] && poster_file="$temp_poster"
                        fi
                        
                        # Use Stremio-style sidebar picker
                        local picker_result
                        if picker_result=$(show_sidebar_picker "$name" "$poster_file" "${torrent_options[@]}" 2>/dev/null); then
                            # User confirmed - keep existing source/magnet/etc
                            [[ -n "$poster_file" ]] && rm -f "$poster_file" 2>/dev/null
                        else
                            # User cancelled
                            [[ -n "$poster_file" ]] && rm -f "$poster_file" 2>/dev/null
                            selection=""
                            redraw_catalog_page "$title" "$cached_results_var" "$current_page" "$per_page" "$total"
                            continue
                        fi
                    fi
                    
                    # Validate magnet link
                    magnet=$(echo "$magnet" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    if [ -z "$magnet" ] || [[ ! "$magnet" =~ ^magnet: ]]; then
                        echo -e "${RED}Error:${RESET} Invalid or missing magnet link for selected torrent"
                        echo -e "${YELLOW}Debug info:${RESET}"
                        echo "  Source: $source"
                        echo "  Name: $name"
                        echo "  Magnet: '$magnet'"
                        sleep 2
                        redraw_catalog_page "$title" "$cached_results_var" "$current_page" "$per_page" "$total"
                        selection=""
                        continue
                    fi
                    
                    # Debug output
                    if [ "$TORRENT_DEBUG" = true ]; then
                        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                        echo -e "${CYAN}DEBUG MODE${RESET}"
                        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                        echo -e "${YELLOW}Selected torrent:${RESET}"
                        echo "  Index: $selection"
                        echo "  Source: $source"
                        echo "  Name: $name"
                        echo "  Quality: $quality"
                        echo "  Size: $size"
                        echo -e "${YELLOW}Magnet link:${RESET}"
                        echo "  $magnet"
                        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                        echo
                    fi
                    
                    echo
                    echo -e "${GREEN}Streaming:${RESET} $name"
                    echo
                    
                    # Check dependencies before streaming
                    if [ -z "$TORRENT_TOOL" ]; then
                        check_deps
                    fi
                    
                    # Stream the selected torrent (subtitles auto-detected)
                    stream_torrent "$magnet" "" false false
                    local exit_code=$?
                    
                    # Exit code 2 means player closed normally - return to catalog
                    if [ $exit_code -eq 2 ]; then
                        # Player closed, return to catalog view
                        redraw_catalog_page "$title" "$cached_results_var" "$current_page" "$per_page" "$total"
                        selection=""
                        continue
                    elif [ $exit_code -ne 0 ]; then
                        # Other error occurred
                        echo
                        echo -e "${YELLOW}Playback failed.${RESET}"
                        echo -e "${YELLOW}Would you like to search for alternative versions of \"$name\"? (y/n)${RESET} "
                        read -r answer
                        if [[ "$answer" =~ ^[Yy]$ ]]; then
                            # Clean up name for search
                            local search_query=$(echo "$name" | tr '.' ' ')
                            search_query=$(echo "$search_query" | sed -E 's/ (1080p|720p|4k|2160p|WEB-DL|BluRay|HDRip|x265|HEVC).*//i')
                            search_query=$(echo "$search_query" | sed -E 's/ \([0-9]{4}\)//')
                            
                            echo -e "${CYAN}Searching for: $search_query${RESET}"
                            search_torrent "$search_query"
                        fi
                        # Redraw catalog after search or if user said no
                        redraw_catalog_page "$title" "$cached_results_var" "$current_page" "$per_page" "$total"
                        selection=""
                        continue
                    else
                        # Player exited normally (exit code 0) - also return to catalog
                        redraw_catalog_page "$title" "$cached_results_var" "$current_page" "$per_page" "$total"
                        selection=""
                        continue
                    fi
                    
                    # Exit navigation loop after selection
                    break
                else
                    echo -e "${YELLOW}Invalid selection. Please enter a number between 1 and $total.${RESET}"
                    sleep 1
                    redraw_catalog_page "$title" "$cached_results_var" "$current_page" "$per_page" "$total"
                    selection=""
                fi
            fi
        done
        
        # Cleanup
        unset CATALOG_PAGE
        eval "unset ${cached_results_var}"
        cleanup_posters
    fi
}
