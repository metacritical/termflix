#!/usr/bin/env bash
#
# Termflix FZF Catalog Module
# Replaces the manual sidebar logic with FZF
#

# Format display line for FZF (show clean movie name with source badges)
format_fzf_display() {
    local index="$1"
    local source="$2"
    local title="$3"
    
    # Extract clean title (remove quality/year info for cleaner display)
    local clean_title="$title"
    
    # Create source badge
    local badge=""
    if [[ "$source" == "COMBINED" ]]; then
        # For COMBINED entries, extract sources from the full line
        # We'll get this from the 4th field
        local rest="$4"
        IFS='|' read -r sources _ <<< "$rest"
        
        # Convert caret-delimited sources to badges
        IFS='^' read -ra sources_arr <<< "$sources"
        for src in "${sources_arr[@]}"; do
            case "$src" in
                "YTS")   badge+="[YTS]" ;;
                "TPB")   badge+="[TPB]" ;;
                "EZTV")  badge+="[EZTV]" ;;
                "1337x") badge+="[1337x]" ;;
            esac
        done
    else
        case "$source" in
            "YTS")   badge="[YTS]" ;;
            "TPB")   badge="[TPB]" ;;
            "EZTV")  badge="[EZTV]" ;;
            "1337x") badge="[1337x]" ;;
        esac
    fi
    
    # Return formatted line: "index. [BADGE] Title"
    printf "%3d. %-20s %s" "$index" "$badge" "$clean_title"
}

show_fzf_catalog() {
    local title="$1"
    local arr_name="$2"
    
    # 1. Prepare Data for FZF
    local fzf_input=""
    local fzf_display=""
    local i=0
    local len
    eval "len=\${#$arr_name[@]}"
    
    for ((j=0; j<len; j++)); do
         local result
         eval "result=\"\${$arr_name[$j]}\""
         
         ((i++))
         # Store the full data line
         fzf_input+="$i|$result"$'\n'
         
         # Parse for display
         IFS='|' read -r source name rest <<< "$result"
         
         # Create clean display line - just number and title
         local display_line
         display_line=$(printf "%3d. %s" "$i" "$name")
         
         # Store full data for preview
         fzf_display+="$display_line|$i|$result"$'\n'
    done

    # 2. Configure FZF with enhanced options
    export FZF_DEFAULT_OPTS="
      --ansi
      --color=fg:#f8f8f2,bg:-1,hl:#ff79c6
      --color=fg+:#ffffff,bg+:#44475a,hl+:#ff79c6
      --color=info:#bd93f9,prompt:#50fa7b,pointer:#ff79c6
      --color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4
      --layout=reverse
      --border=rounded
      --margin=1
      --padding=1
      --prompt='❯ '
      --pointer='▶'
      --header='$title - [$len results]'
      --header-first
      --preview-window=right:55%:wrap:border-left
      --bind='ctrl-/:toggle-preview'
      --bind='alt-j:preview-down,alt-k:preview-up'
      --bind='ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up'
      --bind='ctrl-g:first'
      --bind='ctrl-h:toggle-preview,ctrl-l:toggle-preview'
    "
    
    
    # Debug: show what we're sending to FZF
    if [[ "$TORRENT_DEBUG" == "true" ]]; then
        echo "=== fzf_display content (first 200 chars) ===" >&2
        echo -ne "$fzf_display" | head -c 200 >&2
        echo "" >&2
        echo "=== Total lines: $(echo -ne "$fzf_display" | wc -l) ===" >&2
    fi
    
    # 3. Locate Preview Script
    local preview_script="${SCRIPT_DIR}/modules/ui/preview_fzf.sh"
    
    # 3.5. Launch background precache for first 50 movies
    local precache_script="${SCRIPT_DIR}/scripts/precache_catalog.py"
    if [[ -f "$precache_script" ]] && command -v python3 &>/dev/null; then
        # Pipe catalog data to precache script in background
        printf "%s" "$fzf_input" | python3 "$precache_script" 50 &>/dev/null &
        disown 2>/dev/null
    fi
    
    # 4. Run FZF  
    # Important: Use printf instead of echo -ne for better handling
    local selection
    selection=$(printf "%s" "$fzf_display" | fzf \
        --delimiter='|' \
        --with-nth=1 \
        --preview "$preview_script {3..}" \
        --expect=ctrl-l,ctrl-o,enter \
        --exit-0 2>/dev/null)
        
    # 5. Handle Result
    if [[ -n "$selection" ]]; then
        # Parse output: first line is key, second is selection
        local key
        local selected_line
        { read -r key; read -r selected_line; } <<< "$selection"
        
        # If no selection line (e.g. only key was output), return fail
        [[ -z "$selected_line" ]] && return 1

        # Extract the actual data (everything after first |)
         IFS='|' read -r _ index rest <<< "$selected_line"
         echo "$key|$index|$rest"
         return 0
    else
        return 1
    fi
}

handle_fzf_selection() {
    local selection_line="$1"
    
    [[ -z "$selection_line" ]] && return 1

    # First extract key, index and the actual result data
    # selection_line format: "key|index|result_data..."
    local key index rest_data
    IFS='|' read -r key index rest_data <<< "$selection_line"
    
    # Now parse rest_data which starts with source
    local source name magnet quality size seeds poster
    IFS='|' read -r source name magnet quality size seeds poster <<< "$rest_data"

     # Check if item is COMBINED (multiple sources)
     if [[ "$source" == "COMBINED" ]]; then
         # rest_data format: COMBINED|Name|Sources|Qualities|Seeds|Sizes|Magnets|Poster|IMDBRating|Plot
         local c_name c_sources c_qualities c_seeds c_sizes c_magnets c_poster c_imdb c_plot
         IFS='|' read -r _ c_name c_sources c_qualities c_seeds c_sizes c_magnets c_poster c_imdb c_plot <<< "$rest_data"
         
         # Split into arrays
         IFS='^' read -ra sources_arr <<< "$c_sources"
         IFS='^' read -ra qualities_arr <<< "$c_qualities"
         IFS='^' read -ra seeds_arr <<< "$c_seeds"
         IFS='^' read -ra sizes_arr <<< "$c_sizes"
         IFS='^' read -ra magnets_arr <<< "$c_magnets"
         
         name="$c_name"
         poster="$c_poster"
         
         # Prepare version options for "Right Pane" FZF with nice formatting
         local options=""
         local RESET=$'\e[0m'
         local GREEN=$'\e[38;5;46m'
         local YELLOW=$'\e[38;5;220m'
         local RED=$'\e[38;5;196m'
         
         for i in "${!magnets_arr[@]}"; do
             local src="${sources_arr[$i]:-Unknown}"
             local qual="${qualities_arr[$i]:-N/A}"
             local sz="${sizes_arr[$i]:-N/A}"
             local sd="${seeds_arr[$i]:-0}"
             
             # Color seeds based on count (green=high, yellow=medium, red=low)
             local seed_color
             if [[ "$sd" -ge 100 ]]; then
                 seed_color="$GREEN"
             elif [[ "$sd" -ge 10 ]]; then
                 seed_color="$YELLOW"
             else
                 seed_color="$RED"
             fi
             
             # Source name mapping
             local src_name="Unknown"
             case "$src" in
                 "TPB") src_name="ThePirateBay" ;;
                 "YTS") src_name="YTS.mx" ;;
                 "1337x") src_name="1337x" ;;
                 "EZTV") src_name="EZTV" ;;
                 *) src_name="$src" ;;
             esac
             
             # Format display: 🧲 [TPB] 1080p - 1.4GB - 👥 6497 seeds - ThePirateBay
             local d_line="🧲 [${src}] ${qual} - ${sz} - 👥 ${seed_color}${sd} seeds${RESET} - ${src_name}"
             # Format: idx|display|name|src|qual|sz|poster (for preview to use)
             options+="${i}|${d_line}|${name}|${src}|${qual}|${sz}|${c_poster}"$'\n'
         done
         
         # Launch "Right Pane" Version Picker (Stage 2)
         # Only if multiple magnets OR user explicitly navigated
         if [[ ${#magnets_arr[@]} -ge 1 ]]; then
             local ver_pick
             local stage2_preview
             
             # Detect terminal type for Stage 2 preview
             if [[ "$TERM" == "xterm-kitty" ]]; then
                 # Kitty: Use poster + info preview
                 stage2_preview="${SCRIPT_DIR}/modules/ui/preview_stage2_kitty.sh"
                 local preview_data="${name}|${sources_arr[0]}|${qualities_arr[0]}|${sizes_arr[0]}|${c_poster}"
             else
                 # Block mode: Use large poster only preview
                 stage2_preview="${SCRIPT_DIR}/modules/ui/preview_stage2_block.sh"
                 local preview_data="${name}|${c_poster}"
             fi
             
             # Stage 2 FZF - Same styling as Stage 1 for seamless feel
             ver_pick=$(printf "%s" "$options" | fzf \
                 --ansi \
                 --delimiter='|' \
                 --with-nth=2 \
                 --height=100% \
                 --layout=reverse \
                 --border=rounded \
                 --margin=1 \
                 --padding=1 \
                 --prompt="▶ Pick Version: " \
                 --header="🎬 Available Versions: (Ctrl+H to back)" \
                 --color=fg:#f8f8f2,bg:-1,hl:#ff79c6 \
                 --color=fg+:#ffffff,bg+:#44475a,hl+:#ff79c6 \
                 --color=prompt:#50fa7b,pointer:#ff79c6 \
                 --preview "$stage2_preview '{3}|{4}|{5}|{6}|{7}'" \
                 --preview-window=left:45%:wrap \
                 --bind='ctrl-h:abort,ctrl-o:abort' \
                 2>/dev/null)
             
             if [[ -z "$ver_pick" ]]; then
                 return 10  # Signal BACK to caller
             fi
             
             # Extract index from hidden first field
             local pick_idx
             pick_idx=$(echo "$ver_pick" | cut -d'|' -f1)
             
             # Get selected values
             magnet="${magnets_arr[$pick_idx]}"
             source="${sources_arr[$pick_idx]}"
             quality="${qualities_arr[$pick_idx]}"
         fi
     fi
     
     # Stream Selection
     tput reset 2>/dev/null || clear
     echo -e "${GREEN}Streaming:${RESET} $name"
     echo -e "${CYAN}Source:${RESET} $source  ${CYAN}Size:${RESET} $size  ${CYAN}Quality:${RESET} $quality"
     echo
     
     if [ -z "$TORRENT_TOOL" ]; then
          check_deps
     fi
     stream_torrent "$magnet" "" false false
}
