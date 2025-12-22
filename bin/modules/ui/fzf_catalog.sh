#!/usr/bin/env bash
#
# Termflix FZF Catalog Module
# Replaces the manual sidebar logic with FZF
#

# Resolve module directory (needed for season picker and preview scripts)
FZF_CATALOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
         name="${name%|}"  # Strip any trailing |
         
         # Check watch history - extract magnet hash from rest data
         local watched_icon=""
         local magnet_hash=""
         if [[ "$rest" =~ btih:([a-fA-F0-9]+) ]]; then
             magnet_hash="${BASH_REMATCH[1]}"
             magnet_hash=$(echo "$magnet_hash" | tr '[:upper:]' '[:lower:]')
             # Check if this hash exists in watch history
             if [[ -f "${HOME}/.config/termflix/watch_history.json" ]]; then
                 if command -v jq &>/dev/null; then
                     local pct=$(jq -r --arg h "$magnet_hash" '.[$h].percentage // 0' "${HOME}/.config/termflix/watch_history.json" 2>/dev/null)
                     [[ "$pct" =~ ^[0-9]+$ ]] && [[ "$pct" -gt 0 ]] && watched_icon="➤ "
                 fi
             fi
         fi
         
         # Display line with watched indicator
         local display_line
         display_line=$(printf "%3d. %s%s" "$i" "$watched_icon" "$name")
         
         # Store full data for preview snapshot (use tab as separator for FZF to hide)
         fzf_display+="${display_line}"$'\t'"${i}|${result}"$'\n'
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
    
    # Determine selected tab based on CURRENT_CATEGORY (env) or Title pattern
    # CURRENT_CATEGORY takes priority since it's set by the main loop
    case "${CURRENT_CATEGORY:-}" in
        movies)     hl_movies="o" ;;
        shows)      hl_shows="o" ;;
        all)        hl_movies=" "; hl_shows=" " ;;  # Neither highlighted for "All" mode
        *)
            # Fallback: pattern match on title
            case "$title" in
                *"Movies"*)     hl_movies="o" ;;
                *"Shows"*|*"TV"*) hl_shows="o" ;;
                *"Watchlist"*|*"Library"*) hl_watchlist="o" ;;
                *)              hl_movies="o" ;; # Default
            esac
            ;;
    esac
    
    # Colors for header - Use THEME variables with fallbacks
    local H_RESET=$'\e[0m'
    local H_PINK="${THEME_GLOW:-$'\e[38;2;232;121;249m'}"
    local H_PURPLE="${THEME_PURPLE:-$'\e[38;2;139;92;246m'}"
    local H_CYAN="${THEME_INFO:-$'\e[38;2;94;234;212m'}"
    local H_MUTED="${THEME_FG_MUTED:-$'\e[38;2;107;114;128m'}"
    local H_SEL="${THEME_ACCENT:-$'\e[1;38;2;232;121;249m'}"
    local H_UL=$'\e[4m'
    local H_KEY="${THEME_SUCCESS:-$'\e[1;38;2;94;234;212m'}"
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
    # Build header with LOGO + underlined shortcuts: o=Movies, S=Shows, W=Watchlist, T=Type, V=Sort, G=Genre
    menu_header="${logo}  $(fmt_btn "$hl_movies" "M" "o" "vies") $(fmt_btn "$hl_shows" "" "S" "hows") $(fmt_btn "$hl_watchlist" "" "W" "atchlist") $(fmt_drop "$hl_type" "" "T" "ype") $(fmt_drop "$hl_sort" "Sort [" "V" "]") $(fmt_drop "$hl_genre" "" "G" "enre")"
    
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
    
    # Build page indicator: show '+' if still prefetching or more pages might exist
    local page_suffix=""
    if [[ -n "${TERMFLIX_PREFETCH_PID:-}" ]] && kill -0 "$TERMFLIX_PREFETCH_PID" 2>/dev/null; then
        page_suffix="?"  # Currently prefetching
    elif [[ "${TERMFLIX_NO_MORE_PAGES:-}" != "true" ]]; then
        page_suffix="+"  # More pages might exist
    fi
    
    export FZF_DEFAULT_OPTS="
      --ansi
      --color=${fzf_colors}
      --layout=reverse

      --border=rounded
      --margin=1
      --padding=1
      --info=hidden
      --prompt=\"< Page ${current_page}/${total_pages}${page_suffix} > \"
      --pointer='➤'
      --color=pointer:#ff79c6:bold
      --header=\"$menu_header\"
      --header-first
      --preview-window=right:50%:wrap:border-left
      --border-label=\" ⌨ Enter:Select  Ctrl+J/K:Nav  </>:Page  Ctrl+T:Type  Ctrl+V:Sort  Ctrl+F:Search  Ctrl+E:Season \"
      --border-label-pos=bottom
      --bind='ctrl-/:toggle-preview'
      --bind='ctrl-d:preview-down,ctrl-u:preview-up'
    "


    
    
    # Debug: show what we're sending to FZF
    if [[ "$TORRENT_DEBUG" == "true" ]]; then
        echo "=== fzf_display content (first 200 chars) ===" >&2
        echo -ne "$fzf_display" | head -c 200 >&2
        echo "" >&2
        echo "=== Total lines: $(echo -ne "$fzf_display" | wc -l) ===" >&2
    fi
    
    # 3. Locate Preview Script
    local preview_script="${FZF_CATALOG_DIR}/preview_fzf.sh"
    
    # 3.5. Launch background precache for first 50 movies
    local precache_script="${FZF_CATALOG_DIR}/../../scripts/precache_catalog.py"
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
    
    # Season picker path (for Ctrl+E binding)
    local season_picker="${FZF_CATALOG_DIR}/season_picker.sh"
    
    # 4. Run FZF
    # Important: Use printf instead of echo -ne for better handling
    local selection
    local fzf_exit_code=0
    selection=$(printf "%s" "$fzf_display" | fzf \
        --delimiter=$'\t' \
        --with-nth=1 \
        --preview "$preview_script {2..}" \
        --expect=ctrl-l,ctrl-o,ctrl-s,ctrl-w,ctrl-t,ctrl-v,ctrl-r,ctrl-g,ctrl-f,enter,\>,\<,ctrl-right,ctrl-left \
        --bind "ctrl-e:execute(${FZF_CATALOG_DIR}/season_picker.sh {2..})+reload(printf '%s' \"$fzf_display\")" \
        $pos_bind \
        --exit-0 2>/dev/null)
    fzf_exit_code=$?
        
    # 5. Handle Result
    echo "$(date): FZF selection captured: '$selection'" >> /tmp/fzf_debug.log
    echo "$(date): FZF command exit code: $fzf_exit_code" >> /tmp/fzf_debug.log

    # Check if FZF was cancelled (exit code 130) or had no selection
    if [[ $fzf_exit_code -eq 130 ]] || [[ -z "$selection" ]]; then
        return 1
    fi

    # Parse output: first line is key, second is selection
    local key
    local selected_line
    { read -r key; read -r selected_line; } <<< "$selection"
    echo "$(date): Key: '$key', Selection: '$selected_line'" >> /tmp/fzf_debug.log

    # Handle category switching shortcuts - return exit codes for main loop
    # Keybindings: ^O=mOvies, ^S=Shows, ^W=Watchlist, ^T=Type, ^V=Sort, ^R=Refresh, ^G=Genre
    case "$key" in
        ctrl-o) return 101 ;;  # mOvies
        ctrl-s) return 102 ;;  # Shows
        ctrl-w) return 103 ;;  # Watchlist
        ctrl-t) return 104 ;;  # Type dropdown
        ctrl-v) return 105 ;;  # Sort dropdown
        ctrl-g) return 106 ;;  # Genre dropdown
        ctrl-f) return 110 ;;  # Search
        # ctrl-e is now handled internally via --bind execute
        ctrl-r) return 109 ;;  # Refresh
        ">"|ctrl-right) return 107 ;;  # Next page
        "<"|ctrl-left) return 108 ;;   # Previous page
    esac
        
        # If no selection line (e.g. only key was output), return fail
    [[ -z "$selected_line" ]] && return 1

    # Extract the actual data (format: display<TAB>index|rest)
    local display_part data_part
    IFS=$'\t' read -r display_part data_part <<< "$selected_line"
    IFS='|' read -r index rest <<< "$data_part"
    echo "$key|$index|$rest"
    return 0
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
    
    # Now parse rest_data based on whether it is a COMBINED entry or standard
    local source name magnet quality size seeds poster imdb plot
    if [[ "$rest_data" == "COMBINED"* ]]; then
        # COMBINED format: source|name|sources|qualities|seeds|sizes|magnets|poster|imdb|genre|count
        local sources qualities all_seeds all_sizes magnets genre count
        IFS='|' read -r source name sources qualities all_seeds all_sizes magnets poster imdb genre count <<< "$rest_data"
        # For multi-stage, we use name as title
        magnet="$magnets"
        quality="$qualities"
        size="$all_sizes"
        seeds="$all_seeds"
        plot="$genre" # Or use genre as plot for now if plot is not in COMBINED
    else
        # Standard format
        IFS='|' read -r source name magnet quality size seeds poster imdb plot <<< "$rest_data"
    fi

    # === SHOWS MULTI-STAGE HANDLING (STREMIO-STYLE) ===
    # Identify as series if from Shows category or manually tagged
    local is_series="false"
    # Convert category to lowercase for comparison
    local cat_lower=$(echo "${current_category:-}" | tr '[:upper:]' '[:lower:]')
    [[ "$cat_lower" == "shows" ]] && is_series="true"
    [[ "$name" == *"[SERIES]"* ]] && is_series="true"

    if [[ "$is_series" == "true" ]]; then
        # Robustly clean series name: remove [SERIES], years, quality tags
        local series_name=$(echo "$name" | sed -E '
            s/\[SERIES\]//gi;
            s/\((19|20)[0-9]{2}\)//g;
            s/[[:space:]]+(19|20)[0-9]{2}//g;
            s/[[:space:]]+$//;
            s/^[[:space:]]+//
        ')
        local imdb_id="$imdb"
        local tmdb_id=""
        
        # 1. Get TMDB ID from IMDB ID
        if [[ -n "$imdb_id" && "$imdb_id" != "N/A" ]]; then
            local tmdb_res
            tmdb_res=$(find_by_imdb_id "$imdb_id")
            tmdb_id=$(echo "$tmdb_res" | jq -r '.id // empty' 2>/dev/null)
        fi
        
        # Fallback to name search if no IMDB ID or ID lookup failed
        if [[ -z "$tmdb_id" ]]; then
            local tmdb_res
            tmdb_res=$(search_tmdb_tv "$series_name")
            tmdb_id=$(echo "$tmdb_res" | jq -r '.id // empty' 2>/dev/null)
        fi
        
        if [[ -n "$tmdb_id" ]]; then
            # 2. Get Series Metadata (to find latest season)
            local series_details
            series_details=$(get_tv_details "$tmdb_id")
            
            # Default to latest season with episodes (checking season_number > 0)
            local latest_season
            latest_season=$(echo "$series_details" | jq -r '(.seasons | map(select(.season_number > 0)) | last).season_number // empty' 2>/dev/null)
            
            # If no seasons found or failed, exit
            if [[ -z "$latest_season" ]]; then
                echo -e "${RED}No seasons found for $series_name.${RESET}"
                sleep 2
                return 1
            fi

            # Define show metadata for later use
            local show_poster=""
            local poster_path=$(echo "$series_details" | jq -r '.poster_path // ""' 2>/dev/null)
            [[ -n "$poster_path" && "$poster_path" != "null" ]] && show_poster="https://image.tmdb.org/t/p/w500${poster_path}"
            
            local current_s_num="$latest_season"
            
            # OUTER LOOP: Series Interaction (Season -> Episode -> Version -> Back)
            while true; do
                local picker_path="${SCRIPT_DIR}/modules/ui/episode_picker.sh"
                local picker_output
                picker_output=$("$picker_path" "$series_name" "$imdb_id" "$current_s_num")
                
                # Check for explicit BACK command from picker
                if [[ "$picker_output" == "BACK" ]] || [[ -z "$picker_output" ]]; then
                    return 1 # Back to Catalog
                fi
                
                # 1. Handle Season Switching
                if [[ "$picker_output" == "SWITCH_SEASON" ]]; then
                    local s_picker_path="${SCRIPT_DIR}/modules/ui/season_picker.sh"
                    local new_s
                    new_s=$("$s_picker_path" "$series_name" "$imdb_id")
                    if [[ -n "$new_s" ]]; then
                        current_s_num="$new_s"
                    fi
                    continue # Re-launch episode picker with new season
                fi
                
                # 2. Handle Episode Selection
                if [[ "$picker_output" == "SELECTED_EPISODE|"* ]]; then
                    local e_num_picked="${picker_output#SELECTED_EPISODE|}"
                    local search_query=$(printf "%s S%02dE%02d" "$series_name" "$current_s_num" "$e_num_picked")
                    
                    echo -e "${CYAN}Searching for ${YELLOW}$search_query${RESET}${CYAN}...${RESET}"
                    
                    # --- Data Fetching (Use Cache Logic) ---
                    local search_results=""
                    # Re-implementing the cache-first logic here:
                    
                     # PRIMARY: Try EZTV Cached Data first
                    local eztv_cache="/tmp/tf_eztv_${imdb_id#tt}.json"
                    if [[ -f "$eztv_cache" ]]; then
                        local ep_pattern=$(printf "S%02dE%02d" "$current_s_num" "$e_num_picked")
                        while read -r torrent_line; do
                            [[ -z "$torrent_line" ]] && continue
                            local t_name=$(echo "$torrent_line" | jq -r '.title // .filename')
                            local t_seeds=$(echo "$torrent_line" | jq -r '.seeds // 0')
                            local t_bytes=$(echo "$torrent_line" | jq -r '.size_bytes // 0')
                            local t_magnet=$(echo "$torrent_line" | jq -r '.magnet_url // ""')
                            local t_size=$(awk "BEGIN {printf \"%.0fMB\", $t_bytes/1024/1024}")
                            local t_qual="Unknown"
                            [[ "$t_name" == *"1080p"* ]] && t_qual="1080p"
                            [[ "$t_name" == *"720p"* ]] && t_qual="720p"
                            [[ "$t_name" == *"480p"* ]] && t_qual="480p"
                            # We use show_poster for list, but export specific ep details later
                            local entry="COMBINED|${t_name}|EZTV|${t_qual}|${t_seeds}|${t_size}|${t_magnet}|${show_poster:-N/A}|${imdb_id}|Shows|1"
                            [[ -z "$search_results" ]] && search_results="$entry" || search_results+=$'\n'"$entry"
                        done < <(cat "$eztv_cache" | jq -c --arg ep "$ep_pattern" '.torrents[]? | select(.filename | test($ep; "i"))')
                    fi

                    # SECONDARY: Fallback
                    if [[ -z "$search_results" && -n "$imdb_id" && "$imdb_id" != "N/A" ]]; then
                        local imdb_num="${imdb_id#tt}"
                        local eztv_resp=$(curl -s --max-time 8 "https://eztv.yt/api/get-torrents?imdb_id=${imdb_num}&limit=100" 2>/dev/null)
                        if [[ -n "$eztv_resp" && "$eztv_resp" != *"error"* ]]; then
                            local ep_pattern=$(printf "S%02dE%02d" "$current_s_num" "$e_num_picked")
                            while read -r torrent_line; do
                                [[ -z "$torrent_line" ]] && continue
                                local t_name=$(echo "$torrent_line" | cut -d'|' -f1)
                                local t_seeds=$(echo "$torrent_line" | cut -d'|' -f3)
                                local t_size=$(echo "$torrent_line" | cut -d'|' -f4)
                                local t_magnet=$(echo "$torrent_line" | cut -d'|' -f5)
                                local t_qual="Unknown"
                                [[ "$t_name" == *"1080p"* ]] && t_qual="1080p"
                                [[ "$t_name" == *"720p"* ]] && t_qual="720p"
                                [[ "$t_name" == *"480p"* ]] && t_qual="480p"
                                local entry="COMBINED|${t_name}|EZTV|${t_qual}|${t_seeds}|${t_size}|${t_magnet}|${show_poster:-N/A}|${imdb_id}|Shows|1"
                                [[ -z "$search_results" ]] && search_results="$entry" || search_results+=$'\n'"$entry"
                            done < <(echo "$eztv_resp" | jq -r --arg ep "$ep_pattern" '.torrents[]? | select(.filename | test($ep; "i")) | "\(.title // .filename)|\(.seeds // 0)|\((.size_bytes // 0) / 1024 / 1024 | floor)MB|\(.magnet_url // "")"' 2>/dev/null)
                        fi
                    fi
                    
                    # ADDITIONAL SOURCE: ALWAYS search TPB for more results (parallel with EZTV)
                    local fetcher_script="${TERMFLIX_SCRIPTS_DIR:-$(dirname "$0")/../scripts}/fetch_multi_source_catalog.py"
                    local tpb_results=$(python3 "$fetcher_script" --query "$search_query" --limit 15 --category shows 2>/dev/null | grep "^COMBINED")
                    
                    # Merge TPB results with EZTV results
                    if [[ -n "$tpb_results" ]]; then
                        if [[ -n "$search_results" ]]; then
                            search_results+=$'\n'"$tpb_results"
                        else
                            search_results="$tpb_results"
                        fi
                    fi
                    
                    if [[ -n "$search_results" ]]; then
                        # Aggregate ALL search results into a single COMBINED entry for Stage 2 Version Picker
                        local all_sources="" all_qualities="" all_seeds="" all_sizes="" all_magnets=""
                        local first_name="" torrent_count=0
                        
                        while IFS='|' read -r _ t_name t_src t_qual t_seeds t_size t_magnet _ _ _ _; do
                            [[ -z "$first_name" ]] && first_name="$t_name"
                            torrent_count=$((torrent_count + 1))
                            if [[ -z "$all_sources" ]]; then
                                all_sources="$t_src"; all_qualities="$t_qual"; all_seeds="$t_seeds"; all_sizes="$t_size"; all_magnets="$t_magnet"
                            else
                                all_sources="${all_sources}^${t_src}"; all_qualities="${all_qualities}^${t_qual}"; all_seeds="${all_seeds}^${t_seeds}"; all_sizes="${all_sizes}^${t_size}"; all_magnets="${all_magnets}^${t_magnet}"
                            fi
                        done <<< "$search_results"
                        
                        rest_data="COMBINED|${first_name}|${all_sources}|${all_qualities}|${all_seeds}|${all_sizes}|${all_magnets}|${show_poster:-N/A}|${imdb_id:-N/A}|Shows|${torrent_count}"
                        
                        # --- PREPARE STAGE 3 PREVIEW DATA ---
                        # Extract clean Episode Title & Plot from SEASON_DETAILS (if available from previous step env?)
                        # We need to re-fetch season details if not persistent, OR define a way to get it.
                        # Luckily, episode_picker already did this. We can use `fzf_catalog.sh` cached methods if needed, 
                        # but simple TMDB fetch is safest to ensure fresh data.
                        
                        # Fetch episode details for preview
                        local ep_details=$(get_tv_season_details "$tmdb_id" "$current_s_num" | jq -c --argjson n "$e_num_picked" '.episodes[] | select(.episode_number == $n)')
                        local ep_title=$(echo "$ep_details" | jq -r '.name')
                        local ep_plot=$(echo "$ep_details" | jq -r '.overview // "No description"')
                        local ep_rating=$(echo "$ep_details" | jq -r '.vote_average // "N/A"')
                        
                        export TERMFLIX_STAGE2_TITLE="${ep_title} - [${series_name}] - S$(printf '%02d' "$current_s_num")E$(printf '%02d' "$e_num_picked")"
                        export TERMFLIX_STAGE2_PLOT="${ep_plot}"
                        export TERMFLIX_STAGE2_IMDB="${ep_rating}"
                        # Try EZTV episode screenshot first, then TMDB still, then series poster
                        local poster_file=""
                        local small_screenshot="" large_screenshot="" tmdb_still=""
                        local ep_pattern=$(printf "S%02dE%02d" "$current_s_num" "$e_num_picked")
                        
                        # Extract episode screenshots from EZTV cache
                        if [[ -f "$eztv_cache" ]]; then
                            small_screenshot=$(jq -r --arg ep "$ep_pattern" '.torrents[]? | select(.filename | test($ep; "i")) | .small_screenshot | select(. != "" and . != null)' "$eztv_cache" 2>/dev/null | head -1)
                            large_screenshot=$(jq -r --arg ep "$ep_pattern" '.torrents[]? | select(.filename | test($ep; "i")) | .large_screenshot | select(. != "" and . != null)' "$eztv_cache" 2>/dev/null | head -1)
                            # Fix URLs (EZTV uses protocol-relative URLs starting with //)
                            [[ -n "$small_screenshot" && "$small_screenshot" == "//"* ]] && small_screenshot="https:${small_screenshot}"
                            [[ -n "$large_screenshot" && "$large_screenshot" == "//"* ]] && large_screenshot="https:${large_screenshot}"
                        fi
                        
                        # Fallback: Try TMDB episode still image
                        if [[ -z "$small_screenshot" ]]; then
                            local still_path=$(echo "$ep_details" | jq -r '.still_path // empty' 2>/dev/null)
                            if [[ -n "$still_path" && "$still_path" != "null" ]]; then
                                tmdb_still="https://image.tmdb.org/t/p/w500${still_path}"
                            fi
                        fi
                        
                        # Download: EZTV screenshot > TMDB still > series poster
                        local cache_dir="${HOME}/.cache/termflix/posters"; mkdir -p "$cache_dir"
                        local image_url="${small_screenshot:-${tmdb_still:-$show_poster}}"
                        
                        if [[ -n "$image_url" && "$image_url" != "N/A" ]]; then
                            local hash=$(echo -n "$image_url" | python3 -c "import sys,hashlib;print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null)
                            poster_file="${cache_dir}/${hash}.png"
                            [[ ! -f "$poster_file" ]] && curl -sL --max-time 5 "$image_url" -o "$poster_file" 2>/dev/null
                        fi
                        export TERMFLIX_STAGE2_POSTER="$poster_file"
                        export TERMFLIX_STAGE2_LARGE_SCREENSHOT="$large_screenshot"
                        export TERMFLIX_STAGE2_AVAIL=$(echo "$search_results" | cut -d'|' -f4 | sort -u | tr '\n' ' ' | sed 's/ $//;s/ /, /g')
                        export TERMFLIX_STAGE2_SOURCES="EZTV"
                        
                        # --- INLINE VERSION PICKER (Stage 3) ---
                        # We invoke the Generic Stage 2 Logic here via recursion or fallthrough?
                        # Fallthrough breaks the loop logic. 
                        # We MUST process it here to allow loop-back.
                        
                        source="COMBINED" # Mark for logic reuse if needed
                        
                        # ... Proceed to construct options and CALL FZF manually ...
                        # (Minimal logic to show picker and handle back)
                        
                        # [Construction Logic copied/adapted from below]
                        local options=""
                        IFS='^' read -ra sources_arr <<< "$all_sources"
                        IFS='^' read -ra qualities_arr <<< "$all_qualities"
                        IFS='^' read -ra seeds_arr <<< "$all_seeds"
                        IFS='^' read -ra sizes_arr <<< "$all_sizes"
                        IFS='^' read -ra magnets_arr <<< "$all_magnets"
                        
                        # Use theme-aware semantic colors from colors.sh when available
                        local GREEN="${THEME_SUCCESS:-$C_SUCCESS:-$'\e[38;5;46m'}"
                        local YELLOW="${THEME_WARNING:-$C_WARNING:-$'\e[38;5;220m'}"
                        local RED="${THEME_ERROR:-$C_ERROR:-$'\e[38;5;196m'}"
                        local RESET=$'\e[0m'

                        # Create sorted indices by seeds (highest first)
                        local sorted_indices=()
                        for i in "${!seeds_arr[@]}"; do
                            sorted_indices+=("$i:${seeds_arr[$i]}")
                        done
                        # Sort by seeds descending
                        IFS=$'\n' sorted_indices=($(printf '%s\n' "${sorted_indices[@]}" | sort -t: -k2 -rn))
                        unset IFS

                        for entry in "${sorted_indices[@]}"; do
                            local i="${entry%%:*}"
                            local s="${sources_arr[$i]}"; local q="${qualities_arr[$i]}"
                            local sd="${seeds_arr[$i]}"; local sz="${sizes_arr[$i]}"
                            
                            # Color seeds based on count (green=high, yellow=medium, red=low)
                            local seed_color
                            if [[ "$sd" -ge 100 ]]; then
                                seed_color="$GREEN"
                            elif [[ "$sd" -ge 10 ]]; then
                                seed_color="$YELLOW"
                            else
                                seed_color="$RED"
                            fi

                            # Format display - include source from the parsed results
                            local src="${sources_arr[$i]}"
                            local line=$(printf "  🧲 [%-4s] %-8s - %-8s - %s%4s%s seeds" "$src" "$q" "$sz" "$seed_color" "$sd" "$RESET")
                            options+="${i}|${line}"$'\n'
                        done
                        
                        local preview_script="${SCRIPT_DIR}/modules/ui/preview_stage2.sh"
                        
                        # Use theme colors for consistency with Movies Stage 2
                        local fzf_colors="$(get_fzf_colors 2>/dev/null || echo 'fg:#cdd6f4,bg:-1,hl:#f5c2e7,fg+:#cdd6f4,bg+:#5865f2,hl+:#f5c2e7,pointer:#f5c2e7,prompt:#cba6f7')"
                        
                        local v_pick=$(printf '%s' "$options" | fzf --ansi --layout=reverse --border=rounded \
                            --margin=1 --padding=1 \
                            --pointer='➤' \
                            --prompt="> " \
                            --header="Episode: ${ep_title}" \
                            --header-first \
                            --border-label=" ⌨ Enter:Stream  Ctrl+H:Back " \
                            --border-label-pos=bottom \
                            --color="$fzf_colors" \
                            --preview "$preview_script" --preview-window=left:55%:wrap:border-right \
                            --delimiter='|' --with-nth=2 \
                            --expect=ctrl-h,esc)
                            
                        local key_press=$(echo "$v_pick" | head -1)
                        local sel_line=$(echo "$v_pick" | tail -1)
                        
                        if [[ "$key_press" == "ctrl-h" ]] || [[ "$key_press" == "esc" ]] || [[ -z "$sel_line" ]]; then
                            continue # Back to Episode Listing
                        fi
                        
                        # Selected!
                        local idx=$(echo "$sel_line" | cut -d'|' -f1)
                        local mag="${magnets_arr[$idx]}"
                        
                        # STREAM IT - Use same buffer UI as Movies
                        local plot_text="${ep_plot:-}"
                        if [[ -f "$SCRIPT_DIR/modules/streaming/buffer_ui.sh" ]]; then
                            source "$SCRIPT_DIR/modules/streaming/buffer_ui.sh"
                            show_inline_buffer_ui "$ep_title" "${show_poster:-}" "$plot_text" "$mag" "EZTV" "${qualities_arr[$idx]}" "$idx" "$imdb_id"
                        else
                            stream_torrent "$mag" "" false false
                        fi
                        return 0 # Done watching, exit to catalog
                        
                    else
                        echo -e "${RED}No torrents found.${RESET}"
                        sleep 2
                    fi
                fi
            done
            return 1 # Fallback exit
        else
            echo -e "${YELLOW}Metadata not found for $series_name. Falling back to direct search...${RESET}"
            sleep 1
            
            # Use fetch_multi_source_catalog.py directly for raw series search
            local script_path="${TERMFLIX_SCRIPTS_DIR:-$(dirname "$0")/../scripts}/fetch_multi_source_catalog.py"
            [[ ! -f "$script_path" ]] && script_path="$(dirname "${BASH_SOURCE[0]}")/../../scripts/fetch_multi_source_catalog.py"
            
            local search_results
            search_results=$(python3 "$script_path" --query "$series_name" --limit 20 2>/dev/null | grep "^COMBINED")
            
            if [[ -n "$search_results" ]]; then
                rest_data=$(echo "$search_results" | head -1)
                source="COMBINED"
                # Fall through to Stage 2 picker
            else
                echo -e "${RED}No torrents found for $series_name.${RESET}"
                sleep 2
                return 1
            fi
        fi
    fi

    # CTRL+L HANDLER: Force Stage 2 for single-source items
    # When user presses Ctrl+L, convert single source to COMBINED format
    # so Stage 2 version picker shows, preventing auto-play
    if [[ "$key" == "ctrl-l" ]] && [[ "$source" != "COMBINED" ]]; then
        # Wrap single source in COMBINED format for Stage 2
        rest_data="COMBINED|$name|$source|$quality|$seeds|$size|$magnet|$poster|$imdb|$plot"
        source="COMBINED"
    fi

     # Check if item is COMBINED (multiple sources)
     if [[ "$source" == "COMBINED" ]]; then
         # Propagate Stage 1 context into Stage 2 so preview can distinguish
         # between catalog vs search → Stage 2 transitions.
         if [[ "${TORRENT_DEBUG:-false}" == "true" ]]; then
             echo "[DEBUG fzf_catalog] TERMFLIX_STAGE1_CONTEXT=${TERMFLIX_STAGE1_CONTEXT:-}" >&2
         fi
         local stage2_context="catalog"
         if [[ "${TERMFLIX_STAGE1_CONTEXT:-}" == "search" ]]; then
             stage2_context="search"
         fi
         if [[ "${TORRENT_DEBUG:-false}" == "true" ]]; then
             echo "[DEBUG fzf_catalog] Derived stage2_context=$stage2_context" >&2
         fi
         export TERMFLIX_STAGE2_CONTEXT="$stage2_context"
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
         
         # Source watch history module for progress display (Stage 2)
         if [[ -f "$SCRIPT_DIR/modules/watch_history.sh" ]]; then
             source "$SCRIPT_DIR/modules/watch_history.sh"
         fi
         
         # Prepare version options for "Right Pane" FZF with nice formatting
         local options=""
         local RESET=$'\e[0m'
         # Use theme-aware semantic colors from colors.sh when available
         local GREEN="${THEME_SUCCESS:-$C_SUCCESS:-$'\e[38;5;46m'}"
         local YELLOW="${THEME_WARNING:-$C_WARNING:-$'\e[38;5;220m'}"
         local RED="${THEME_ERROR:-$C_ERROR:-$'\e[38;5;196m'}"
         
         for i in "${!magnets_arr[@]}"; do
             local src="${sources_arr[$i]:-Unknown}"
             local qual="${qualities_arr[$i]:-N/A}"
             local sz="${sizes_arr[$i]:-N/A}"
             local sd="${seeds_arr[$i]:-0}"
             local magnet_i="${magnets_arr[$i]}"
             
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
                 "yts_web") src_name="YTS.lt" ;;
                 "1337x") src_name="1337x" ;;
                 "EZTV") src_name="EZTV" ;;
                 *) src_name="$src" ;;
             esac
             
             # Watch history lookup for this magnet (progress bar)
             local watched_indicator=""
             local progress_bar=""
             if command -v extract_torrent_hash &> /dev/null; then
                 local hash
                 hash=$(extract_torrent_hash "$magnet_i")
                 if [[ -n "$hash" ]]; then
                     local pct
                     pct=$(get_watch_percentage "$hash" 2>/dev/null)
                     # pct is empty when there is no history entry for this hash
                     if [[ -n "$pct" ]]; then
                         progress_bar="$(generate_progress_bar "$pct")"
                         # Only mark as "watched" (➤) once there's at least some progress
                         if [[ "$pct" -ge 0 ]]; then
                             watched_indicator="👀"
                         fi
                     fi
                 fi
             fi
             
             # Format display with basic column padding for better alignment
             # Badge [SRC] uses the same per-source colors as Stage 1 (YTS/TPB/1337x/EZTV)
             local d_line
             local src_color=""
             if command -v get_source_color &> /dev/null; then
                 src_color="$(get_source_color "$src")"
             fi
             d_line=$(printf "%-2s %s🧲[%3s]%s %-8s - %-12s - 👥 %s%4s%s seeds %s" \
                 "$watched_indicator" \
                 "${src_color:-$RESET}" "$src" "$RESET" \
                 "$qual" \
                 "$sz" \
                 "$seed_color" "$sd" "$RESET" \
                 "$progress_bar")
             # Format: idx|display (for preview to use)
             options+="${i}|${d_line}"$'\n'
         done
     fi
         
         # Define Streaming Logic Helper within function context
         perform_streaming() {
             local BUFFER_STATUS_FILE="/tmp/termflix_buffer_status.txt"
             rm -f "$BUFFER_STATUS_FILE" 2>/dev/null
             echo "0|0|0|0|0|BUFFERING" > "$BUFFER_STATUS_FILE"
             if [ -z "$TORRENT_TOOL" ]; then check_deps; fi
             export TERMFLIX_BUFFER_STATUS="$BUFFER_STATUS_FILE"
             if [[ -f "$SCRIPT_DIR/modules/streaming/buffer_ui.sh" ]]; then
                 source "$SCRIPT_DIR/modules/streaming/buffer_ui.sh"
                 local plot_text="${c_plot:-$plot}"
                 local ver_idx=""
                 if [[ -n "$ver_pick" ]]; then ver_idx=$(echo "$ver_pick" | cut -d'|' -f1); fi
                 local imdb_id=$(echo "$selection" | grep -oE 'tt[0-9]{7,}' | head -1)
                 show_inline_buffer_ui "$name" "${poster_file:-$poster}" "$plot_text" "$magnet" "$source" "$quality" "$ver_idx" "$imdb_id"
             else
                 stream_torrent "$magnet" "" false false
             fi
             rm -f "$BUFFER_STATUS_FILE" 2>/dev/null
         }

         # Launch "Right Pane" Version Picker (Stage 2)
         # Only if multiple magnets OR user explicitly navigated
         if [[ ${#magnets_arr[@]} -ge 1 ]]; then
             while true; do
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
              
              # Save options to file for Buffer UI reconstruction
              echo "$options" > "${TMPDIR:-/tmp}/termflix_stage2_options.txt"

              if [[ "$TERM" == "xterm-kitty" ]]; then
                  # KITTY MODE: Poster/Sources/Exports already prepared above
                  local stage2_preview="${SCRIPT_DIR}/modules/ui/preview_stage2.sh"
                  
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
                      --pointer='➤' \
                      --header="Pick Version - [${c_name}] →" \
                      --header-first \
                       --color="$(get_fzf_colors 2>/dev/null || echo 'fg:#6b7280,bg:#1e1e2e,hl:#818cf8,fg+:#ffffff,bg+:#5865f2,hl+:#c4b5fd,info:#6b7280,prompt:#5eead4,pointer:#818cf8,marker:#818cf8,spinner:#818cf8,header:#a78bfa,border:#5865f2,gutter:#1e1e2e')" \
                      --preview "TERMFLIX_STAGE2_CONTEXT=\"$stage2_context\" $stage2_preview" \
                      --preview-window=left:55%:wrap:border-right \
                      --bind='ctrl-h:abort,ctrl-o:abort' \
                      --no-select-1 \
                      2>/dev/null)
                      
                  # Cleanup
                  unset STAGE2_POSTER STAGE2_TITLE STAGE2_SOURCES STAGE2_AVAIL STAGE2_PLOT
                  kitten icat --clear 2>/dev/null
              else
                  # BLOCK MODE: Preview on LEFT
                  # Must pass env vars explicitly since FZF subprocess doesn't inherit them
                  local stage2_preview="${SCRIPT_DIR}/modules/ui/preview_stage2.sh"
                  
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
                      --prompt="➤ Pick Version: " \
                      --header="🎬 Available Versions: (Ctrl+H to back)" \
                       --color="$(get_fzf_colors 2>/dev/null || echo 'fg:#6b7280,bg:#1e1e2e,hl:#818cf8,fg+:#ffffff,bg+:#5865f2,hl+:#c4b5fd,info:#6b7280,prompt:#5eead4,pointer:#818cf8,marker:#818cf8,spinner:#818cf8,header:#a78bfa,border:#5865f2,gutter:#1e1e2e')" \
                      --preview "TERMFLIX_STAGE2_CONTEXT=\"$stage2_context\" STAGE2_POSTER=\"$poster_file\" STAGE2_TITLE=\"${c_name//\"/\\\"}\" STAGE2_SOURCES=\"$s_badges\" STAGE2_AVAIL=\"$q_disp\" STAGE2_PLOT=\"${c_plot//\"/\\\"}\" STAGE2_IMDB=\"$c_imdb\" $stage2_preview" \
                       --border-label=" ⌨ Enter:Stream  Ctrl+H:Back  ↑↓:Navigate " \
                       --border-label-pos=bottom \
                      --preview-window=left:55%:wrap \
                      --bind='ctrl-h:abort,ctrl-o:abort' \
                      --no-select-1 \
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
             
             # Stream (Loop back to Stage 2 after)
             perform_streaming
         done
     else
         # Simple Source (Direct Stream)
         perform_streaming
     fi
}
