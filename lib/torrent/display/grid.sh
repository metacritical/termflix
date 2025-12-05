#!/bin/bash
# Grid display functions for torrent catalog
# Handles drawing grid rows with images and text

# Source colors if not already defined
if [ -z "$CYAN" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/colors.sh" 2>/dev/null || true
fi

# Draw a row of up to num_cols items in a grid
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
    local row_height=20  # Total height for one row (image + text)
    
    # Calculate column positions based on terminal width
    local term_cols=$(tput cols)
    local total_cols_needed=$((num_cols * 40))
    local spacing
    if [ "$total_cols_needed" -le "$term_cols" ]; then
        spacing=$((term_cols / num_cols))
    else
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
        
        if [[ -n "$poster_url" ]] && [[ "$poster_url" != "N/A" ]]; then
            local image_file="${temp_dir}/poster_$(echo "$poster_url" | md5 2>/dev/null | cut -c1-8).jpg"
            image_files[$i]="$image_file"
            
            # Download in background if not already cached
            if [ ! -f "$image_file" ]; then
                ( curl -s --max-time 5 "$poster_url" -o "$image_file" 2>/dev/null ) &
                pids+=($!)
            fi
        else
            image_files[$i]=""
        fi
    done
    
    # Wait for all downloads to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null
    done
    
    # Pass 2: Pre-render all images offline
    declare -a has_image=()
    declare -a is_kitty=()
    local image_line_files=()
    
    for i in "${!items[@]}"; do
        local image_file="${image_files[$i]}"
        has_image[$i]=0
        is_kitty[$i]=0
        image_line_files[$i]=""
        
        if [[ -n "$image_file" ]] && [[ -f "$image_file" ]]; then
            if [[ "$TERM" == "xterm-kitty" ]] && command -v kitty &> /dev/null; then
                is_kitty[$i]=1
                has_image[$i]=1
            elif check_viu >/dev/null 2>&1; then
                local rendered_file="${temp_dir}/rendered_${i}.txt"
                viu -w "$img_width" -h "$img_height" "$image_file" 2>/dev/null > "$rendered_file"
                # Sanitize VIU output: remove cursor movement codes but keep colors
                if command -v perl &> /dev/null; then
                    perl -i -pe "s/\x1b\[[0-9;]*[A-HJKSTf]//g" "$rendered_file"
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
    
    # Pass 3: Draw images row by row
    for ((row=0; row<img_height; row++)); do
        for i in "${!items[@]}"; do
            local x_pos="${col_positions[$i]}"
            local current_y=$((start_row + row + 1))
            if [ "$current_y" -ge "$(tput lines)" ]; then continue; fi
            
            if [[ "${has_image[$i]}" -eq 1 ]]; then
                if [[ "${is_kitty[$i]}" -eq 1 ]]; then
                    if [[ "$row" -eq 0 ]]; then
                        local image_file="${image_files[$i]}"
                        kitty +kitten icat --align left --place "${img_width}x${img_height}@${x_pos}x$((start_row + 1))" "$image_file" 2>/dev/null
                    fi
                else
                    local rendered_file="${image_line_files[$i]}"
                    if [[ -n "$rendered_file" ]] && [[ -f "$rendered_file" ]]; then
                        tput cup "$current_y" "$x_pos"
                        local image_line
                        image_line=$(sed -n "$((row + 1))p" "$rendered_file" 2>/dev/null)
                        if [[ -n "$image_line" ]]; then
                            local clean_line="${image_line%$'\n'}"
                            printf "%s" "$clean_line"
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
                # Draw placeholder box
                local image_file="${image_files[$i]}"
                if [[ -z "$image_file" ]] || [[ ! -f "$image_file" ]]; then
                    tput cup "$current_y" "$x_pos"
                    if [[ "$row" -eq 0 ]]; then
                        echo -ne "${CYAN}┌──────────────────┐${RESET}"
                    elif [[ "$row" -eq $((img_height-1)) ]]; then
                        echo -ne "${CYAN}└──────────────────┘${RESET}"
                    elif [[ "$row" -eq 7 ]]; then
                        echo -ne "${CYAN}│${RESET}"
                        tput cup "$current_y" $((x_pos + 5))
                        echo -ne "${CYAN}No Poster${RESET}"
                        tput cup "$current_y" $((x_pos + 19))
                        echo -ne "${CYAN}│${RESET}"
                    else
                        echo -ne "${CYAN}│                  │${RESET}"
                    fi
                    tput cup "$current_y" $((x_pos + 20))
                fi
            fi
        done
        # Move cursor to next line after each image row
        if [ "$row" -lt $((img_height - 1)) ]; then
            local next_y=$((start_row + row + 2))
            tput cup "$next_y" 0
        else
            local text_start_y=$((start_row + img_height + 1))
            tput cup "$text_start_y" 0
            tput el
        fi
    done
    
    # Calculate text row position
    if [ "$start_row" -lt 1 ]; then
        start_row=1
    fi
    
    local image_start_row=$((start_row + 1))
    local image_end_row=$((start_row + img_height))
    local text_row=$((image_end_row + 1))
    
    if [ "$text_row" -le "$image_end_row" ]; then
        text_row=$((image_end_row + 1))
    fi
    
    if [ "$text_row" -lt 1 ]; then
        text_row=$((start_row + 20))
        if [ "$text_row" -lt 1 ]; then
            text_row=20
        fi
    fi
    
    # Clear text rows
    tput cup "$image_end_row" 0
    tput el
    tput cup "$text_row" 0
    tput el
    tput cup $((text_row + 1)) 0
    tput el
    tput cup $((text_row + 2)) 0
    tput el
    tput cup "$text_row" 0
    
    # Pass 4: Draw text below images
    local term_cols=$(tput cols)
    
    for i in "${!items[@]}"; do
        local item="${items[$i]}"
        local x_pos="${col_positions[$i]}"
        IFS='|' read -r source name magnet quality size extra poster_url <<< "$item"
        
        local item_num=$((start_index + i + 1))
        local source_color="$CYAN"
        case "$source" in
            YTS) source_color="$GREEN" ;;
            TPB) source_color="$YELLOW" ;;
            EZTV) source_color="$BLUE" ;;
            1337x) source_color="$MAGENTA" ;;
        esac
        
        local display_name="${name:0:38}"
        if [ "${#name}" -gt 38 ]; then
            display_name="${display_name}..."
        fi
        
        local next_x
        if [ "$i" -lt $((${#items[@]} - 1)) ]; then
            next_x="${col_positions[$((i + 1))]}"
        else
            next_x=$term_cols
        fi
        local col_width=$((next_x - x_pos - 1))
        if [ "$col_width" -gt 35 ]; then col_width=35; fi
        if [ "$col_width" -lt 20 ]; then col_width=20; fi
        
        local safe_x_pos=$x_pos
        if [ "$safe_x_pos" -lt 1 ]; then
            safe_x_pos=1
        fi
        
        local actual_text_row=$text_row
        if [ "$actual_text_row" -le "$image_end_row" ]; then
            actual_text_row=$((image_end_row + 1))
        fi
        
        local term_lines_check=$(tput lines)
        if [ "$actual_text_row" -ge "$term_lines_check" ] || [ "$actual_text_row" -lt 1 ]; then 
            continue
        fi
        
        # Row 1: [num] [source]
        tput cup "$actual_text_row" "$safe_x_pos"
        local clear_end=$next_x
        if [ "$clear_end" -gt "$term_cols" ]; then
            clear_end=$term_cols
        fi
        printf "%*s" $((clear_end - safe_x_pos)) ""
        tput cup "$actual_text_row" "$safe_x_pos"
        printf "${BOLD}[%d]${RESET} ${source_color}[%s]${RESET}" "$item_num" "$source"
        
        # Row 2: Movie name
        local text_row_2=$((actual_text_row + 1))
        if [ "$text_row_2" -le "$image_end_row" ]; then
            text_row_2=$((image_end_row + 1))
        fi
        tput cup "$text_row_2" "$safe_x_pos"
        printf "%*s" $((clear_end - safe_x_pos)) ""
        tput cup "$text_row_2" "$safe_x_pos"
        local truncated_name="${display_name:0:$col_width}"
        if [ "${#display_name}" -gt "$col_width" ]; then
            truncated_name="${truncated_name}..."
        fi
        printf "${BOLD}%s${RESET}" "$truncated_name"
        
        # Row 3: Quality and size
        local text_row_3=$((actual_text_row + 2))
        if [ "$text_row_3" -le "$image_end_row" ]; then
            text_row_3=$((image_end_row + 1))
        fi
        tput cup "$text_row_3" "$safe_x_pos"
        printf "%*s" $((clear_end - safe_x_pos)) ""
        tput cup "$text_row_3" "$safe_x_pos"
        
        local quality_size_parts=()
        if [ -n "$quality" ] && [ "$quality" != "N/A" ]; then
             quality_size_parts+=("$quality")
        fi
        if [ -n "$size" ] && [ "$size" != "N/A" ]; then
             quality_size_parts+=("$size")
        fi
        
        local quality_size_clean=""
        if [ ${#quality_size_parts[@]} -gt 0 ]; then
            local IFS=" | "
            quality_size_clean="${quality_size_parts[*]}"
        fi
        
        if [ "${#quality_size_clean}" -gt "$col_width" ]; then
            quality_size_clean="${quality_size_clean:0:$col_width}..."
        fi
        
        if [ -n "$quality_size_clean" ]; then
            printf "${CYAN}%s${RESET}" "$quality_size_clean"
        fi
        
        tput cup "$text_row_3" $((next_x - 1))
    done
    
    # Cleanup rendered files
    for rendered_file in "${image_line_files[@]}"; do
        [[ -n "$rendered_file" ]] && rm -f "$rendered_file" 2>/dev/null
    done
    
    # Calculate next row position
    # Layout: start_row + img_height (15) + spacing (1) + text_lines (3) = start_row + 19
    # But we use row_height=20 for consistency
    local next_row=$((start_row + row_height))
    
    # CRITICAL: Ensure next_row is valid
    local term_lines_check=$(tput lines)
    if [ "$next_row" -lt 1 ]; then
        next_row=$((start_row + row_height))
    fi
    if [ "$next_row" -gt "$term_lines_check" ]; then
        # If beyond terminal, calculate relative to terminal size
        next_row=$((term_lines_check - 5))
        if [ "$next_row" -lt 1 ]; then
            next_row=1
        fi
    fi
    
    # Position cursor at next row
    # Don't suppress output completely, but ensure it doesn't interfere
    if [ "$next_row" -ge 1 ] && [ "$next_row" -lt "$(tput lines)" ]; then
        tput cup "$next_row" 0 2>/dev/null || true
    fi
    
    # Return next row via stderr (so it doesn't interfere with display)
    echo "$next_row" >&2
}
