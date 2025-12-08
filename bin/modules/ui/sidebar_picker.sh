#!/usr/bin/env bash
#
# Termflix Sidebar Picker Module
# Stremio-style two-column layout: poster left, selector right
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_SIDEBAR_LOADED:-}" ]] && return 0
_TERMFLIX_SIDEBAR_LOADED=1

# ═══════════════════════════════════════════════════════════════
# SIDEBAR PICKER
# ═══════════════════════════════════════════════════════════════

# Global result variable (set after show_sidebar_picker returns)
SIDEBAR_PICKER_RESULT=""

# Show Stremio-style torrent selection picker
# Two-column layout: poster on left, torrent list on right
# Args: movie_name poster_path torrent1 torrent2 ...
# Torrents format: source|quality|seeds|size|magnet
# Returns: 0 on selection, 1 on cancel
# Sets SIDEBAR_PICKER_RESULT to selected index (0-based)
show_sidebar_picker() {
    local movie_name="$1"
    local poster_path="$2"
    shift 2
    local -a torrents=("$@")
    
    local num_items=${#torrents[@]}
    SIDEBAR_PICKER_RESULT=""
    
    # Get terminal dimensions
    local term_cols=$(tput cols)
    local term_rows=$(tput lines)
    local left_width=$((term_cols * 40 / 100))
    local right_width=$((term_cols * 55 / 100))
    local poster_height=$((term_rows - 10))
    
    # Build display options for gum
    local -a display_options=()
    
    for i in "${!torrents[@]}"; do
        # Parse torrent: source|quality|seeds|size|magnet
        IFS='|' read -r src quality seeds size magnet <<< "${torrents[$i]}"
        
        # Format display line
        local display_line="${seeds:-0} seeds │ ${quality:-N/A} │ ${size:-N/A} │ ${src:-Unknown}"
        display_options+=("$display_line")
    done
    
    # Check if gum is available
    if command -v gum &>/dev/null; then
        # ═══════════════════════════════════════════════════════════
        # GUM-BASED TWO-COLUMN LAYOUT
        # ═══════════════════════════════════════════════════════════
        
        clear
        
        # Create left panel content (poster + movie title)
        local left_panel_file=$(mktemp)
        local right_panel_file=$(mktemp)
        
        # Generate left panel (poster area)
        {
            echo ""
            if [[ -f "$poster_path" ]] && command -v viu &>/dev/null; then
                viu -w $((left_width - 4)) -h $((poster_height - 4)) "$poster_path" 2>/dev/null
            else
                # Placeholder for no poster
                for ((i=0; i<poster_height/2-2; i++)); do echo ""; done
                gum style --width $((left_width - 4)) --align center "🎬 No Poster"
            fi
            echo ""
            # Movie title at bottom
            echo "$movie_name" | head -c $((left_width - 4))
        } > "$left_panel_file"
        
        # Style the left panel with border
        local styled_left
        styled_left=$(gum style \
            --border rounded \
            --border-foreground 135 \
            --width $left_width \
            --height $((term_rows - 4)) \
            --padding "0 1" \
            "$(cat "$left_panel_file")")
        
        # Print left panel (it will stay visible)
        echo "$styled_left"
        
        # Position cursor for right panel
        tput cup 0 $((left_width + 2))
        
        # Show the gum selector in a styled box
        local header
        header=$(gum style --foreground 135 --bold "Available Torrents")
        
        # Show selection with gum choose
        local selected
        selected=$(printf '%s\n' "${display_options[@]}" | \
            gum choose \
                --header "$header" \
                --cursor.foreground 212 \
                --selected.foreground 212 \
                --height $((term_rows - 8)) \
                --cursor "➤ " \
                --cursor-prefix "  " \
                --unselected-prefix "  ")
        
        # Cleanup temp files
        rm -f "$left_panel_file" "$right_panel_file" 2>/dev/null
        
        if [[ -z "$selected" ]]; then
            # User cancelled (Ctrl+C or ESC)
            return 1
        fi
        
        # Find the index of selected option
        for i in "${!display_options[@]}"; do
            if [[ "${display_options[$i]}" == "$selected" ]]; then
                SIDEBAR_PICKER_RESULT="$i"
                return 0
            fi
        done
        
        return 1
    else
        # ═══════════════════════════════════════════════════════════
        # FALLBACK: Simple numbered selection (no gum)
        # ═══════════════════════════════════════════════════════════
        
        clear
        echo -e "\n${C_GLOW:-\033[38;5;212m}${BOLD:-\033[1m}$movie_name${RESET:-\033[0m}"
        echo -e "${C_PURPLE:-\033[38;5;135m}────────────────────────────────────────${RESET:-\033[0m}\n"
        
        echo -e "${C_SUBTLE:-\033[38;5;245m}Available torrents:${RESET:-\033[0m}\n"
        
        for i in "${!display_options[@]}"; do
            echo -e "  ${C_GLOW:-\033[38;5;212m}$((i+1)))${RESET:-\033[0m} ${display_options[$i]}"
        done
        
        echo ""
        echo -n "Enter choice [1-${num_items}] or 'q' to cancel: "
        read -r choice
        
        if [[ "$choice" == "q" ]] || [[ "$choice" == "Q" ]]; then
            return 1
        fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le $num_items ]]; then
            SIDEBAR_PICKER_RESULT=$((choice - 1))
            return 0
        fi
        
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# EXPORT FUNCTIONS
# ═══════════════════════════════════════════════════════════════

export -f show_sidebar_picker
export SIDEBAR_PICKER_RESULT
