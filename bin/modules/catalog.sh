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
                        # DISABLED: This causes Kitty protocol errors to leak into FZF
                        # kitty +kitten icat --align left --place "${img_width}x${img_height}@${x_pos}x$((start_row + 1))" "$image_file" 2>/dev/null
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
            local cache_dir=$(get_cache_dir)/tmdb
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
                            local new_poster=$(fetch_google_poster "$clean_title" "$year")
                            echo "$new_poster" > "$temp_file"
                        ) &
                        pids+=($!)
                    fi
                else
                    local cache_dir=$(get_cache_dir)/tmdb
                    local cache_key=$(echo "${clean_title}_${year}" | tr -cd '[:alnum:]')
                    local cache_file="$cache_dir/${cache_key}.json"
                    
                    if [ ! -f "$cache_file" ] && [ -n "$clean_title" ]; then
                        (
                            fetch_google_poster "$clean_title" "$year" > /dev/null 2>&1
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
# Usage: display_catalog <title> [gum] [function args...]
# If 'gum' is passed as the second parameter, use gum-based display
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
    
    # FZF Catalog Logic with Navigation Loop
    # -------------------------------------------------------------------------
    while true; do
        local selection_line
        selection_line=$(show_fzf_catalog "$title" all_results)
        local fzf_ret=$?
        
        # Handle category switching return codes (101-106)
        # New keybindings: ^M=Movies, ^S=Shows, ^W=Watchlist, ^T=Type, ^O=Sort, ^G=Genre
        case $fzf_ret in
            101) return 101 ;;  # Movies (^M)
            102) return 102 ;;  # Shows (^S)
            103) return 103 ;;  # Watchlist (^W)
            104) return 104 ;;  # Type dropdown (^T)
            105) return 105 ;;  # Sort dropdown (^O)
            106) return 106 ;;  # Genre dropdown (^G)
            1)   return 0 ;;    # FZF cancelled (Esc/Ctrl-C)
        esac
        
        # Normal selection handling (fzf_ret=0 with output)
        if [ -n "$selection_line" ]; then
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
# CATALOG FETCHING LOGIC
# ============================================================

# Get latest movies - Multi-source (YTS + TPB)
# Uses Python script to aggregate torrents from multiple sources
get_latest_movies() {
    local limit="${1:-50}"
    local page="${2:-1}"
    
    # Use multi-source Python script (combines YTS + TPB)
    local script_path="${TERMFLIX_SCRIPTS_DIR:-$(dirname "$0")/../scripts}/fetch_multi_source_catalog.py"
    [[ ! -f "$script_path" ]] && script_path="$(dirname "${BASH_SOURCE[0]}")/../scripts/fetch_multi_source_catalog.py"
    
    if [[ -f "$script_path" ]] && command -v python3 &>/dev/null; then
        python3 "$script_path" --limit "$limit" --page "$page" 2>/dev/null
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
    
    # Use multi-source Python script with download_count sort (trending)
    local script_path="${TERMFLIX_SCRIPTS_DIR:-$(dirname "$0")/../scripts}/fetch_multi_source_catalog.py"
    [[ ! -f "$script_path" ]] && script_path="$(dirname "${BASH_SOURCE[0]}")/../scripts/fetch_multi_source_catalog.py"
    
    if [[ -f "$script_path" ]] && command -v python3 &>/dev/null; then
        python3 "$script_path" --limit "$limit" --page "$page" --sort download_count 2>/dev/null
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
# Uses same approach as YTS-Streaming app
# Supports pagination via page parameter
get_popular_movies() {
    local limit="${1:-50}"
    local page="${2:-1}"
    
    # Build URL the same way as YTS-Streaming app (with pagination)
    local base_url="https://yts.lt/api/v2/list_movies.json"
    local api_url="${base_url}?limit=${limit}&sort_by=rating&order_by=desc&minimum_rating=7&page=${page}"
    
    if command -v curl &> /dev/null && command -v jq &> /dev/null; then
        local response=$(curl -s --max-time 3 --connect-timeout 2 \
            -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
            -H "Accept: application/json" \
            "$api_url" 2>/dev/null)
        
        if [ -n "$response" ] && [ "$response" != "" ]; then
            local status=$(echo "$response" | jq -r '.status // "fail"' 2>/dev/null)
            
            if [ "$status" = "ok" ]; then
                local results=$(echo "$response" | jq -r '.data.movies[]? | select(.torrents != null and (.torrents | length) > 0) | .torrents[0] as $torrent | select($torrent.hash != null and $torrent.hash != "") | "YTS|\(.title) (\(.year)) - ⭐\(.rating // "N/A")|magnet:?xt=urn:btih:\($torrent.hash)|\($torrent.quality // "N/A")|\($torrent.size // "N/A")|\(.rating // "N/A")|\(.medium_cover_image // "N/A")"' 2>/dev/null | head -20)
                
                if [ -n "$results" ]; then
                    echo "$results"
                    return 0
                fi
            fi
        fi
    fi
    
    # Fallback to TPB popular
    echo -e "${YELLOW}[TPB]${RESET} YTS unavailable, using ThePirateBay popular..." >&2
    local tpb_url="https://apibay.org/precompiled/data_top100_205.json"
    if command -v curl &> /dev/null && command -v jq &> /dev/null; then
        local tpb_response=$(curl -s --max-time 5 "$tpb_url" 2>/dev/null)
        if [ -n "$tpb_response" ]; then
            # Fetch all available for pagination
            echo "$tpb_response" | jq -r '.[]? | select(.info_hash != null and .info_hash != "") | "TPB|\(.name)|magnet:?xt=urn:btih:\(.info_hash)|\(.seeders) seeds|\(.size / 1024 / 1024 | floor)MB|Popular"' 2>/dev/null
        fi
    fi
}

# Get latest TV shows from EZTV (with domain rotation + TPB fallback)
# Supports pagination via page parameter
get_latest_shows() {
    local limit="${1:-50}"
    local page="${2:-1}"
    local has_results=false
    
    # EZTV domains to try (working ones first, fallbacks at end)
    local eztv_domains=("eztvx.to" "eztv.wf" "eztv.yt" "eztv1.xyz" "eztv.tf" "eztv.re")
    
    if command -v curl &> /dev/null && command -v jq &> /dev/null; then
        for domain in "${eztv_domains[@]}"; do
            local api_url="https://${domain}/api/get-torrents?limit=$limit&page=$page"
            local response=$(curl -s --max-time 5 "$api_url" 2>/dev/null)
            local count=$(echo "$response" | jq -r '.torrents_count // 0' 2>/dev/null)
            
            if [ "$count" -gt 0 ] 2>/dev/null; then
                echo "$response" | jq -r '.torrents[]? | select(.magnet_url != null and .magnet_url != "") | "EZTV|\(.title)|\(.magnet_url)|\(.seeds) seeds|\(.size_bytes / 1024 / 1024 | floor)MB|\(.date_released_unix // 0)"' 2>/dev/null
                has_results=true
                break  # Stop on first working domain
            fi
        done
    fi
    
    # Fallback to TPB HD TV Shows if all EZTV domains failed
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
# Uses same approach as YTS-Streaming app
get_catalog_by_genre() {
    local genre="$1"
    local limit="${2:-20}"
    
    # Map common genre names to YTS genre IDs (same as YTS-Streaming)
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
    
    # Build URL the same way as YTS-Streaming app
    local base_url="https://yts.lt/api/v2/list_movies.json"
    local api_url="${base_url}?genre=${genre_id}&limit=${limit}&sort_by=date_added&order_by=desc"
    
    if command -v curl &> /dev/null && command -v jq &> /dev/null; then
        # Add User-Agent header like browsers do
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
# For the "New" category (^N keybinding)
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

