#!/usr/bin/env bash
#
# Termflix FZF Catalog Module
# Replaces the manual sidebar logic with FZF
#

show_fzf_catalog() {
    local title="$1"
    local arr_name="$2"
    
    # 1. Prepare Data for FZF
    # Format: Index|Source|Title|Quality|Size|Magnet|Extra|PosterURL
    # We pipe this into FZF
    
    local fzf_input=""
    local i=0
    local len
    eval "len=\${#$arr_name[@]}"
    
    for ((j=0; j<len; j++)); do
         local result
         eval "result=\"\${$arr_name[$j]}\""
         
         # Assuming result format from search/catalog functions:
         # Source|Name|Magnet|Quality|Size|Extra|PosterURL
         # We prepend Index for selection logic
         ((i++))
         fzf_input+="$i|$result"$'\n'
    done

    # 2. Configure FZF Colors (Charm Palette)
    # Pink/Magenta Accents
    # fg:#c0c0c0,bg:-1,hl:#ff79c6
    # fg+:#ffffff,bg+:#44475a,hl+:#ff79c6
    export FZF_DEFAULT_OPTS="
      --color=fg:#f8f8f2,bg:-1,hl:#ff79c6
      --color=fg+:#ffffff,bg+:#44475a,hl+:#ff79c6
      --color=info:#bd93f9,prompt:#50fa7b,pointer:#ff79c6
      --color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4
      --layout=reverse
      --border=rounded
      --margin=1
      --padding=1
      --prompt='Search > '
      --pointer='➤ '
      --header='$title'
      --preview-window=right:50%:wrap
    "
    
    # 3. Locate Preview Script
    # Use global TERMFLIX_SCRIPTS_DIR or relative fallback
    local preview_script="${SCRIPT_DIR}/modules/ui/preview_fzf.sh"
    
    # 4. Run FZF
    # --with-nth=3 : Show Title (3rd field) in list
    # --delimiter='\|' : Field separator
    # --preview : Call our preview script with the full line ({})
    
    local selection
    selection=$(echo -ne "$fzf_input" | fzf \
        --delimiter='\|' \
        --with-nth=2,3 \
        --preview "$preview_script {}" \
        --exit-0 --select-1)
        
    # 5. Handle Result
    if [[ -n "$selection" ]]; then
        echo "$selection"
        return 0
    else
        return 1
    fi
}

handle_fzf_selection() {
    local selection_line="$1"
    
    [[ -z "$selection_line" ]] && return 1

    IFS='|' read -r index source name magnet quality size extra poster <<< "$selection_line"

     # Check if item is COMBINED
     if [[ "$source" == "COMBINED" ]]; then
         # Format: COMBINED|Name|Sources|Qualities|Seeds|Sizes|Magnets|Poster
         IFS='|' read -r _ c_name c_sources c_qualities c_seeds c_sizes c_magnets c_poster <<< "$selection_line"
         
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
         
         # Use Gum to select version (Charm style)
         local gum_opts=()
         for i in "${!sources_arr[@]}"; do
             gum_opts+=("$((i+1)). [${sources_arr[$i]}] ${qualities_arr[$i]} - ${sizes_arr[$i]} (${seeds_arr[$i]} seeds)")
         done
         
         local choice=$(printf "%s\n" "${gum_opts[@]}" | gum choose --header "Select Version for $c_name" --cursor="➤ " --cursor.foreground="212" --header.foreground="212")
         
         if [[ -n "$choice" ]]; then
             local choice_num=$(echo "$choice" | cut -d'.' -f1)
             local idx=$((choice_num - 1))
             
             source="${sources_arr[$idx]}"
             magnet="${magnets_arr[$idx]}"
             quality="${qualities_arr[$idx]}"
             size="${sizes_arr[$idx]}"
             name="$c_name"
         else
             return 0
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
