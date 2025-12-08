#!/usr/bin/env bash
#
# Termflix Sidebar Picker Module
# Torrent selection using gum (with native bash fallback)
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_SIDEBAR_LOADED:-}" ]] && return 0
_TERMFLIX_SIDEBAR_LOADED=1

# ═══════════════════════════════════════════════════════════════
# SIDEBAR PICKER
# ═══════════════════════════════════════════════════════════════

# Global result variable (set after show_sidebar_picker returns)
SIDEBAR_PICKER_RESULT=""

# Show torrent selection picker
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
    
    # Build display options
    local -a display_options=()
    local -a indices=()
    
    for i in "${!torrents[@]}"; do
        # Parse torrent: source|quality|seeds|size|magnet
        IFS='|' read -r src quality seeds size magnet <<< "${torrents[$i]}"
        
        # Format display line with colors for gum
        local display_line="${seeds:-0} seeds │ ${quality:-N/A} │ ${size:-N/A} │ ${src:-Unknown}"
        display_options+=("$display_line")
        indices+=("$i")
    done
    
    # Check if gum is available
    if command -v gum &>/dev/null; then
        # ═══════════════════════════════════════════════════════════
        # GUM-BASED PICKER (smooth, handles arrow keys natively)
        # ═══════════════════════════════════════════════════════════
        
        clear
        
        # Show movie title header
        echo ""
        gum style --foreground 212 --bold "$movie_name"
        echo ""
        
        # Show poster if available
        if [[ -f "$poster_path" ]] && command -v viu &>/dev/null; then
            viu -w 40 -h 15 "$poster_path" 2>/dev/null
            echo ""
        fi
        
        # Show torrent selection with gum choose
        local selected
        selected=$(printf '%s\n' "${display_options[@]}" | \
            gum choose \
                --header "Select torrent source:" \
                --header.foreground 135 \
                --cursor.foreground 212 \
                --selected.foreground 212 \
                --height 15 \
                --cursor "➤ " \
                --cursor-prefix "  " \
                --unselected-prefix "  ")
        
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
