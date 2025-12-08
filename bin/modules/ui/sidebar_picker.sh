#!/usr/bin/env bash
#
# Termflix Sidebar Picker Module
# Stremio-style torrent selection interface
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_SIDEBAR_LOADED:-}" ]] && return 0
_TERMFLIX_SIDEBAR_LOADED=1

# ═══════════════════════════════════════════════════════════════
# SIDEBAR PICKER
# ═══════════════════════════════════════════════════════════════

# Global result variable (set after show_sidebar_picker returns)
SIDEBAR_PICKER_RESULT=""

# Show Stremio-style sidebar picker for torrent selection
# Args: movie_name poster_path torrent1 torrent2 ...
# Torrents format: source|quality|seeds|size|magnet
# Returns: 0 on selection, 1 on cancel
# Sets SIDEBAR_PICKER_RESULT to selected index (0-based)
show_sidebar_picker() {
    local movie_name="$1"
    local poster_path="$2"
    shift 2
    local -a torrents=("$@")
    
    local term_cols=$(tput cols)
    local term_rows=$(tput lines)
    
    # Layout: 45% left (poster), 55% right (list)
    local left_width=$((term_cols * 45 / 100))
    local right_start=$((left_width + 1))
    local right_width=$((term_cols - right_start - 2))
    
    # State
    local selected=0
    local scroll_offset=0
    local visible_items=$((term_rows - 10))
    local num_items=${#torrents[@]}
    
    # Save terminal state
    save_terminal_state
    tput smcup      # Alternate screen
    tput civis      # Hide cursor
    stty -echo -icanon min 1 time 0
    
    # Local cleanup function
    _sidebar_cleanup() {
        stty echo icanon 2>/dev/null
        tput cnorm 2>/dev/null
        tput rmcup 2>/dev/null
    }
    
    trap '_sidebar_cleanup' RETURN
    
    # Draw function
    _draw_sidebar() {
        clear
        
        # ─── LEFT PANEL: POSTER ───
        if [[ -f "$poster_path" ]] && command -v viu &>/dev/null; then
            tput cup 2 2
            viu -w $((left_width - 4)) -h $((term_rows - 12)) "$poster_path" 2>/dev/null
        else
            # Draw placeholder
            local ph_start=$((term_rows / 2 - 3))
            for i in {0..5}; do
                tput cup $((ph_start + i)) 5
                if [[ $i -eq 2 ]]; then
                    echo -ne "${C_MUTED:-\033[38;5;241m}   🎬 No Poster   ${RESET:-\033[0m}"
                fi
            done
        fi
        
        # Movie title at bottom of left panel
        local title_row=$((term_rows - 6))
        tput cup $title_row 2
        local truncated_name="${movie_name:0:$((left_width-4))}"
        echo -ne "${C_GLOW:-\033[38;5;212m}${BOLD:-\033[1m}${truncated_name}${RESET:-\033[0m}"
        
        # ─── DIVIDER ───
        for ((r=1; r<term_rows-3; r++)); do
            tput cup $r $left_width
            echo -ne "${C_PURPLE:-\033[38;5;135m}│${RESET:-\033[0m}"
        done
        
        # ─── RIGHT PANEL: TORRENT LIST ───
        tput cup 1 $right_start
        echo -ne "${BOLD:-\033[1m}${C_GLOW:-\033[38;5;212m}Available Torrents${RESET:-\033[0m}"
        
        tput cup 2 $right_start
        echo -ne "${C_PURPLE:-\033[38;5;135m}"
        printf '─%.0s' $(seq 1 $((right_width - 2)))
        echo -ne "${RESET:-\033[0m}"
        
        local list_start_row=4
        for ((i=0; i<visible_items && i+scroll_offset<num_items; i++)); do
            local idx=$((i + scroll_offset))
            local row=$((list_start_row + i))
            
            tput cup $row $right_start
            printf "%*s" "$right_width" ""  # Clear line
            tput cup $row $right_start
            
            # Parse torrent: source|quality|seeds|size|magnet
            IFS='|' read -r src quality seeds size magnet <<< "${torrents[$idx]}"
            
            # Source color
            local src_color="${C_SUBTLE:-\033[38;5;245m}"
            case "$src" in
                YTS)   src_color="${C_YTS:-\033[38;5;46m}" ;;
                TPB)   src_color="${C_TPB:-\033[38;5;220m}" ;;
                1337x) src_color="${C_1337X:-\033[38;5;213m}" ;;
                EZTV)  src_color="${C_EZTV:-\033[38;5;81m}" ;;
            esac
            
            if [[ $idx -eq $selected ]]; then
                # Selected row - highlighted
                echo -ne "${C_GLOW:-\033[38;5;212m}➤ ${BOLD:-\033[1m}"
                printf "%-6s seeds   %-8s   %-8s ${src_color}%-6s${RESET:-\033[0m}" \
                    "$seeds" "$quality" "$size" "$src"
            else
                echo -ne "  ${C_SUBTLE:-\033[38;5;245m}"
                printf "%-6s seeds   %-8s   %-8s ${src_color}%-6s${RESET:-\033[0m}" \
                    "$seeds" "$quality" "$size" "$src"
            fi
        done
        
        # Show scroll indicators if needed
        if [[ $scroll_offset -gt 0 ]]; then
            tput cup 3 $((right_start + right_width - 3))
            echo -ne "${C_MUTED:-\033[38;5;241m}▲${RESET:-\033[0m}"
        fi
        if [[ $((scroll_offset + visible_items)) -lt $num_items ]]; then
            tput cup $((list_start_row + visible_items)) $((right_start + right_width - 3))
            echo -ne "${C_MUTED:-\033[38;5;241m}▼${RESET:-\033[0m}"
        fi
        
        # ─── FOOTER ───
        local footer_row=$((term_rows - 3))
        tput cup $footer_row 0
        echo -ne "${C_PURPLE:-\033[38;5;135m}"
        printf '─%.0s' $(seq 1 $term_cols)
        echo -ne "${RESET:-\033[0m}"
        
        tput cup $((footer_row + 1)) 2
        echo -ne "${C_SUBTLE:-\033[38;5;245m}${num_items} sources${RESET:-\033[0m}"
        
        # Navigation hints (centered)
        local hints="j/k or ↑↓: navigate  •  enter: select  •  esc/q: back"
        local hints_col=$(( (term_cols - ${#hints}) / 2 ))
        tput cup $((footer_row + 2)) $hints_col
        echo -ne "${C_MUTED:-\033[38;5;241m}${hints}${RESET:-\033[0m}"
    }
    
    # Main loop
    _draw_sidebar
    while true; do
        IFS= read -rsn1 key
        
        case "$key" in
            j|J)  # Down
                if [[ $selected -lt $((num_items - 1)) ]]; then
                    ((selected++))
                    [[ $((selected - scroll_offset)) -ge $visible_items ]] && ((scroll_offset++))
                    _draw_sidebar
                fi
                ;;
            k|K)  # Up
                if [[ $selected -gt 0 ]]; then
                    ((selected--))
                    [[ $selected -lt $scroll_offset ]] && ((scroll_offset--))
                    _draw_sidebar
                fi
                ;;
            '')  # Enter - select
                _sidebar_cleanup
                SIDEBAR_PICKER_RESULT="$selected"
                return 0
                ;;
            q|Q)  # Quit
                _sidebar_cleanup
                return 1
                ;;
            $'\x1b')  # Escape key or escape sequences
                # Read up to 3 more chars for full escape sequence (e.g., ESC [ A)
                local seq=""
                read -rsn1 -t 0.1 char1
                if [[ -z "$char1" ]]; then
                    # ESC pressed alone - quit
                    _sidebar_cleanup
                    return 1
                fi
                seq="$char1"
                read -rsn1 -t 0.05 char2
                [[ -n "$char2" ]] && seq="${seq}${char2}"
                read -rsn1 -t 0.05 char3
                [[ -n "$char3" ]] && seq="${seq}${char3}"
                
                case "$seq" in
                    '[A'|'OA') # Up arrow
                        if [[ $selected -gt 0 ]]; then
                            ((selected--))
                            [[ $selected -lt $scroll_offset ]] && ((scroll_offset--))
                            _draw_sidebar
                        fi
                        ;;
                    '[B'|'OB') # Down arrow
                        if [[ $selected -lt $((num_items - 1)) ]]; then
                            ((selected++))
                            [[ $((selected - scroll_offset)) -ge $visible_items ]] && ((scroll_offset++))
                            _draw_sidebar
                        fi
                        ;;
                    '[5~') # Page Up
                        selected=$((selected - visible_items))
                        [[ $selected -lt 0 ]] && selected=0
                        scroll_offset=$((scroll_offset - visible_items))
                        [[ $scroll_offset -lt 0 ]] && scroll_offset=0
                        _draw_sidebar
                        ;;
                    '[6~') # Page Down
                        selected=$((selected + visible_items))
                        [[ $selected -ge $num_items ]] && selected=$((num_items - 1))
                        if [[ $((selected - scroll_offset)) -ge $visible_items ]]; then
                            scroll_offset=$((selected - visible_items + 1))
                        fi
                        _draw_sidebar
                        ;;
                esac
                ;;
            # Ctrl+n (next) - Emacs style
            $'\x0e')
                if [[ $selected -lt $((num_items - 1)) ]]; then
                    ((selected++))
                    [[ $((selected - scroll_offset)) -ge $visible_items ]] && ((scroll_offset++))
                    _draw_sidebar
                fi
                ;;
            # Ctrl+p (previous) - Emacs style
            $'\x10')
                if [[ $selected -gt 0 ]]; then
                    ((selected--))
                    [[ $selected -lt $scroll_offset ]] && ((scroll_offset--))
                    _draw_sidebar
                fi
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════
# EXPORT FUNCTIONS
# ═══════════════════════════════════════════════════════════════

export -f show_sidebar_picker
