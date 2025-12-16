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
    local current_page="${3:-1}"
    local total_pages="${4:-1}"
    local start_pos="${5:-1}"  # Cursor start position (1-indexed)
    
    # Note: Image logo via kitten icat doesn't persist as FZF redraws the screen
    # Using text logo "🍿 TERMFLIX™" in the header instead (line ~132)
    
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

    # Persist the last catalog view to temp files so Stage 2
    # (version picker) can reconstruct the static movie list
    # in its left pane, even though this function runs inside
    # a subshell due to command substitution.
    local snap_dir="${TMPDIR:-/tmp}"
    local snap_file="${snap_dir}/termflix_stage1_fzf_display.txt"
    local snap_header_file="${snap_dir}/termflix_stage1_fzf_header.txt"
    printf "%s\n" "$fzf_display" > "$snap_file" 2>/dev/null
    echo "$title - [$len results]" > "$snap_header_file" 2>/dev/null

    # 2. Configure FZF with enhanced options
    # Header showing navigation options - New Design with LOGO
    local hl_movies=" "
    local hl_shows=" "
    local hl_watchlist=" "
    local hl_type=" "
    local hl_sort=" "
    local hl_genre=" "
    
    # Determine selected tab based on Title
    case "$title" in
        *"Movies"*)     hl_movies="o" ;;
        *"Shows"*|*"TV"*) hl_shows="o" ;;
        *"Watchlist"*|*"Library"*) hl_watchlist="o" ;;
        *)              hl_movies="o" ;; # Default
    esac
    
    # Colors for header - Use ANSI-C quoting for proper escape code interpretation
    local H_RESET=$'\e[0m'
    local H_PINK=$'\e[38;2;232;121;249m'     # Hot pink #E879F9
    local H_PURPLE=$'\e[38;2;139;92;246m'    # Purple #8B5CF6
    local H_CYAN=$'\e[38;2;94;234;212m'      # Cyan #5EEAD4
    local H_MUTED=$'\e[38;2;107;114;128m'    # Muted gray
    local H_SEL=$'\e[1;38;2;232;121;249m'    # Bold pink - selection
    local H_UL=$'\e[4m'                       # Underline
    local H_KEY=$'\e[1;38;2;94;234;212m'     # Bold cyan - shortcut key
    local H_ITALIC=$'\e[3m'                   # Italic
    
    # Logo: text with gradient colors
    local logo="🍿 ${H_PINK}TERM${H_PURPLE}FLIX${H_RESET}™"
    
    # Helper for button formatting with underlined + colored shortcut
    # Usage: fmt_btn "state" "prefix" "shortcut" "suffix"
    # Example: fmt_btn "o" "m" "O" "vies" => m[O]vies (O is cyan+underlined)
    fmt_btn() {
        local state="$1"
        local prefix="$2"
        local shortcut="$3"
        local suffix="$4"
        if [[ "$state" == "o" ]]; then
            echo -ne "[${H_SEL}● ${prefix}${H_KEY}${H_UL}${shortcut}${H_RESET}${H_SEL}${suffix}${H_RESET}]"
        else
            echo -ne "[${prefix}${H_KEY}${H_UL}${shortcut}${H_RESET}${suffix}]"
        fi
    }

    # Special formatter for Dropdown with underlined + colored shortcut
    fmt_drop() {
        local state="$1"
        local prefix="$2"
        local shortcut="$3"
        local suffix="$4"
        if [[ "$state" == "o" ]]; then
            echo -ne "[${H_SEL}● ${prefix}${H_KEY}${H_UL}${shortcut}${H_RESET}${H_SEL}${suffix} ▾${H_RESET}]"
        else
            echo -ne "[${prefix}${H_KEY}${H_UL}${shortcut}${H_RESET}${suffix} ▾]"
        fi
    }
    
    local menu_header
    # Build header with LOGO + underlined shortcuts: o=Movies, S=Shows, W=Watchlist, T=Type, r=Sort, G=Genre
    menu_header="${logo}  $(fmt_btn "$hl_movies" "M" "o" "vies") $(fmt_btn "$hl_shows" "" "S" "hows") $(fmt_btn "$hl_watchlist" "" "W" "atchlist") $(fmt_drop "$hl_type" "" "T" "ype") $(fmt_drop "$hl_sort" "So" "r" "t") $(fmt_drop "$hl_genre" "" "G" "enre")"
    
    # Get FZF colors from theme (if theme loader available)
    # Charm-style: blue selection bar, muted gray text, dark background
    local fzf_colors
    if command -v get_fzf_colors &>/dev/null; then
        fzf_colors=$(get_fzf_colors)
    else
        # Charm picker colors: muted gray text, blue highlight bar
        fzf_colors="fg:#6b7280,bg:#1e1e2e,hl:#818cf8"           # Muted gray text, indigo highlight
        fzf_colors+=",fg+:#ffffff,bg+:#5865f2,hl+:#c4b5fd"      # White on blue selection bar
        fzf_colors+=",info:#6b7280,prompt:#5eead4,pointer:#818cf8"  # Muted info, cyan prompt
        fzf_colors+=",marker:#818cf8,spinner:#818cf8,header:#a78bfa" # Indigo accents
        fzf_colors+=",border:#5865f2,gutter:#1e1e2e"            # Blue border
    fi
    
    export FZF_DEFAULT_OPTS="
      --ansi
      --color=${fzf_colors}
      --layout=reverse

      --border=rounded
      --margin=1
      --padding=1
      --info=hidden
      --prompt=\"< Page ${current_page}/${total_pages} > \"
      --pointer='▶'
      --header=\"$menu_header\"
      --header-first
      --preview-window=right:55%:wrap:border-left
      --border-label=\" ⌨ Enter:Select  Ctrl+H:Preview  </> Page  Ctrl+W/T/P/V/G:Categories \"
      --border-label-pos=bottom
      --bind='ctrl-/:toggle-preview'
      --bind='alt-j:preview-down,alt-k:preview-up'
      --bind='ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up'
      --bind='ctrl-h:change-preview-window(hidden|right:55%)'
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
        # Pipe catalog data to precache script in background (suppress ALL output)
        (printf "%s" "$fzf_input" | python3 "$precache_script" 50 >/dev/null 2>&1) &
        disown 2>/dev/null || true
    fi
    
    # Build start position binding if provided
    local pos_bind=""
    if [[ $start_pos -gt 1 ]]; then
        pos_bind="--bind=start:pos($start_pos)"
    fi
    
    # 4. Run FZF  
    # Important: Use printf instead of echo -ne for better handling
    local selection
    selection=$(printf "%s" "$fzf_display" | fzf \
        --delimiter='|' \
        --with-nth=1 \
        --preview "$preview_script {3..}" \
        --expect=ctrl-l,ctrl-o,ctrl-s,ctrl-w,ctrl-t,ctrl-r,ctrl-g,enter,\>,\<,ctrl-right,ctrl-left \
        $pos_bind \
        --exit-0 2>/dev/null)
        
    # 5. Handle Result
    if [[ -n "$selection" ]]; then
        # Parse output: first line is key, second is selection
        local key
        local selected_line
        { read -r key; read -r selected_line; } <<< "$selection"
        
        # Handle category switching shortcuts - return exit codes for main loop
        # Keybindings: ^O=mOvies, ^S=Shows, ^W=Watchlist, ^T=Type, ^R=soRt, ^G=Genre
        case "$key" in
            ctrl-o) return 101 ;;  # mOvies
            ctrl-s) return 102 ;;  # Shows
            ctrl-w) return 103 ;;  # Watchlist
            ctrl-t) return 104 ;;  # Type dropdown
            ctrl-r) return 105 ;;  # soRt dropdown
            ctrl-g) return 106 ;;  # Genre dropdown
            ">"|ctrl-right) return 107 ;;  # Next page
            "<"|ctrl-left) return 108 ;;   # Previous page
        esac
        
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

    # Remember which movie index was active when we jump
    # into Stage 2 so the kitty preview can render the
    # static movie list with the correct selection marker.
    export STAGE2_SELECTED_INDEX="$index"
    
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
             
             # Stage 2 FZF - Version Picker
              # Prepare Poster Path (for both Kitty and Block modes)
              local poster_file=""
              local cache_dir="${HOME}/.cache/termflix/posters"

              # 1) Prefer catalog-provided poster URL (c_poster)
              if [[ -n "$c_poster" && "$c_poster" != "N/A" ]]; then
                  local hash
                  hash=$(echo -n "$c_poster" | python3 -c "import sys,hashlib;print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
                  poster_file="${cache_dir}/${hash}.png"
              fi

              # 2) If catalog had no poster, reuse Stage 1 search cache (search_<title_hash>.url)
              if [[ -z "$poster_file" || ! -f "$poster_file" ]]; then
                  # Compute same title_hash as preview_fzf.sh
                  local title_hash
                  if command -v md5 &>/dev/null; then
                      title_hash=$(echo -n "$c_name" | tr '[:upper:]' '[:lower:]' | md5)
                  elif command -v md5sum &>/dev/null; then
                      title_hash=$(echo -n "$c_name" | tr '[:upper:]' '[:lower:]' | md5sum | cut -d' ' -f1)
                  else
                      title_hash=$(echo -n "$c_name" | tr '[:upper:]' '[:lower:]' | python3 -c "import sys,hashlib;print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
                  fi

                  local search_cache="${cache_dir}/search_${title_hash}.url"
                  if [[ -f "$search_cache" ]]; then
                      local cached_url
                      cached_url=$(cat "$search_cache")
                      if [[ "$cached_url" != "null" && "$cached_url" != "N/A" && -n "$cached_url" ]]; then
                          local hash2
                          hash2=$(echo -n "$cached_url" | python3 -c "import sys,hashlib;print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
                          poster_file="${cache_dir}/${hash2}.png"
                      fi
                  fi
              fi

              # 3) Fallback to built-in image
              [[ ! -f "$poster_file" ]] && poster_file="${SCRIPT_DIR}/../lib/termflix/img/movie_night.jpg"
              [[ ! -f "$poster_file" ]] && poster_file=""

              # Prepare Sources/Available strings (for both Kitty and Block modes)
              local unique_sources=($(printf "%s\n" "${sources_arr[@]}" | sort -u))
              local s_badges=""
              for s in "${unique_sources[@]}"; do s_badges+="[${s}]"; done

              local q_disp=""
              local seen_q=()
              for i in "${!qualities_arr[@]}"; do
                  local q="${qualities_arr[$i]}"
                  local sz="${sizes_arr[$i]}"
                  if [[ ! " ${seen_q[@]} " =~ " ${q} " ]]; then
                      seen_q+=("$q")
                      [[ -n "$q_disp" ]] && q_disp+=", "
                      q_disp+="${q} (${sz})"
                  fi
              done

              # Export variables for BOTH preview scripts (Kitty and Block)
              export STAGE2_POSTER="$poster_file"
              export STAGE2_TITLE="$c_name"
              export STAGE2_SOURCES="$s_badges"
              export STAGE2_AVAIL="$q_disp"
              export STAGE2_PLOT="$c_plot"
              export STAGE2_IMDB="$c_imdb"

              if [[ "$TERM" == "xterm-kitty" ]]; then
                  # KITTY MODE: Poster/Sources/Exports already prepared above
                  local stage2_preview="${SCRIPT_DIR}/modules/ui/preview_stage2_kitty.sh"
                  
                  # 5. Run FZF w/ Left Pane Preview (Picker on Right)
                  ver_pick=$(printf "%s" "$options" | fzf \
                      --ansi \
                      --delimiter='|' \
                      --with-nth=2 \
                      --height=100% \
                      --layout=reverse \
                      --border=rounded \
                      --margin=1 \
                      --padding=1 \
                      --prompt='❯ ' \
                      --pointer='▶' \
                      --header="Pick Version - [${c_name}] →" \
                      --header-first \
                      --color=fg:#f8f8f2,bg:-1,hl:#ff79c6 \
                      --color=fg+:#ffffff,bg+:#44475a,hl+:#ff79c6 \
                      --color=info:#bd93f9,prompt:#50fa7b,pointer:#ff79c6 \
                      --preview "$stage2_preview" \
                      --preview-window=left:55%:wrap:border-right \
                      --bind='ctrl-h:abort,ctrl-o:abort' \
                      2>/dev/null)
                      
                  # Cleanup
                  unset STAGE2_POSTER STAGE2_TITLE STAGE2_SOURCES STAGE2_AVAIL STAGE2_PLOT
                  kitten icat --clear 2>/dev/null
              else
                  # BLOCK MODE: Preview on LEFT
                  # Must pass env vars explicitly since FZF subprocess doesn't inherit them
                  local stage2_preview="${SCRIPT_DIR}/modules/ui/preview_stage2_block.sh"
                  
                  ver_pick=$(STAGE2_POSTER="$poster_file" \
                             STAGE2_TITLE="$c_name" \
                             STAGE2_SOURCES="$s_badges" \
                             STAGE2_AVAIL="$q_disp" \
                             STAGE2_PLOT="$c_plot" \
                             STAGE2_IMDB="$c_imdb" \
                             printf "%s" "$options" | fzf \
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
                      --color=fg:#f8f8f2,bg:-1,hl:#E879F9 \
                      --color=fg+:#ffffff,bg+:#2d1f3d,hl+:#E879F9 \
                      --color=prompt:#5EEAD4,pointer:#E879F9 \
                      --border-label=" ⌨ Enter:Stream  Ctrl+H:Back  ↑↓:Navigate " \
                      --border-label-pos=bottom \
                      --preview "STAGE2_POSTER=\"$poster_file\" STAGE2_TITLE=\"${c_name//\"/\\\"}\" STAGE2_SOURCES=\"$s_badges\" STAGE2_AVAIL=\"$q_disp\" STAGE2_PLOT=\"${c_plot//\"/\\\"}\" STAGE2_IMDB=\"$c_imdb\" $stage2_preview" \
                      --preview-window=left:45%:wrap \
                      --bind='ctrl-h:abort,ctrl-o:abort' \
                      2>/dev/null)
              fi
             
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
     # Create buffer status file to show progress in preview pane
     local BUFFER_STATUS_FILE="/tmp/termflix_buffer_status.txt"
     
     # Clean up any old status
     rm -f "$BUFFER_STATUS_FILE" 2>/dev/null
     
     # Write initial buffering status
     echo "0|0|0|0|0|BUFFERING" > "$BUFFER_STATUS_FILE"
     
     tput reset 2>/dev/null || clear
     echo -e "${GREEN}Streaming:${RESET} $name"
     echo -e "${CYAN}Source:${RESET} $source  ${CYAN}Size:${RESET} $size  ${CYAN}Quality:${RESET} $quality"
     echo
     
     if [ -z "$TORRENT_TOOL" ]; then
          check_deps
     fi
     
     # Export buffer status file path for streaming module
     export TERMFLIX_BUFFER_STATUS="$BUFFER_STATUS_FILE"
     
     stream_torrent "$magnet" "" false false
     
     # Clean up buffer status after streaming ends
     rm -f "$BUFFER_STATUS_FILE" 2>/dev/null
}
