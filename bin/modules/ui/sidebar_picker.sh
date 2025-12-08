#!/usr/bin/env bash
#
# Termflix Sidebar Picker Module
# Stremio-style two-column layout: poster left, gum selector right
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
    
    local term_cols=$(tput cols)
    local term_rows=$(tput lines)
    
    # Layout: 45% left (poster), 55% right (list)
    local left_width=$((term_cols * 45 / 100))
    local right_start=$((left_width + 2))
    local right_width=$((term_cols - right_start - 2))
    
    local num_items=${#torrents[@]}
    SIDEBAR_PICKER_RESULT=""
    
    # Build display options
    local -a display_options=()
    
    for i in "${!torrents[@]}"; do
        IFS='|' read -r src quality seeds size magnet <<< "${torrents[$i]}"
        local display_line="${seeds:-0} seeds │ ${quality:-N/A} │ ${size:-N/A} │ ${src:-Unknown}"
        display_options+=("$display_line")
    done
    
    # Enter alternate screen
    tput smcup
    clear
    
    # ─── LEFT PANEL: POSTER ───
    if [[ -f "$poster_path" ]] && command -v viu &>/dev/null; then
        tput cup 3 2
        viu -w $((left_width - 4)) -h $((term_rows - 12)) "$poster_path" 2>/dev/null
    else
        # Draw placeholder
        local ph_row=$((term_rows / 2 - 2))
        tput cup $ph_row 2
        echo -e "${C_MUTED:-\033[38;5;241m}   🎬 No Poster${RESET:-\033[0m}"
    fi
    
    # Movie title at bottom of left panel
    local title_row=$((term_rows - 5))
    tput cup $title_row 2
    local truncated_name="${movie_name:0:$((left_width-4))}"
    echo -e "${C_GLOW:-\033[38;5;212m}${BOLD:-\033[1m}${truncated_name}${RESET:-\033[0m}"
    
    # ─── DIVIDER ───
    for ((r=1; r<term_rows-2; r++)); do
        tput cup $r $left_width
        echo -ne "${C_PURPLE:-\033[38;5;135m}│${RESET:-\033[0m}"
    done
    
    # ─── RIGHT PANEL HEADER ───
    tput cup 1 $right_start
    echo -e "${BOLD:-\033[1m}${C_GLOW:-\033[38;5;212m}Available Torrents${RESET:-\033[0m}"
    
    tput cup 2 $right_start
    echo -ne "${C_PURPLE:-\033[38;5;135m}"
    printf '─%.0s' $(seq 1 $((right_width - 2)))
    echo -ne "${RESET:-\033[0m}"
    
    # ─── FOOTER ───
    local footer_row=$((term_rows - 2))
    tput cup $footer_row 0
    echo -ne "${C_PURPLE:-\033[38;5;135m}"
    printf '─%.0s' $(seq 1 $term_cols)
    echo -ne "${RESET:-\033[0m}"
    
    tput cup $((footer_row + 1)) 2
    echo -ne "${C_SUBTLE:-\033[38;5;245m}${num_items} sources${RESET:-\033[0m}"
    
    local hints="↑↓ navigate • enter select • esc back"
    local hints_col=$(( (term_cols - ${#hints}) / 2 ))
    tput cup $((footer_row + 1)) $hints_col
    echo -ne "${C_MUTED:-\033[38;5;241m}${hints}${RESET:-\033[0m}"
    
    # ─── RIGHT PANEL: GUM SELECTOR ───
    # Position cursor for gum
    tput cup 4 $right_start
    
    # Use gum for selection
    local selected=""
    if command -v gum &>/dev/null; then
        # Run gum choose for the selection
        selected=$(printf '%s\n' "${display_options[@]}" | \
            gum choose \
                --cursor.foreground 212 \
                --selected.foreground 212 \
                --height $((term_rows - 10)) \
                --cursor "➤ " \
                --cursor-prefix "  " \
                --unselected-prefix "  " 2>/dev/null)
    else
        # Fallback: numbered selection
        echo ""
        for i in "${!display_options[@]}"; do
            echo "  $((i+1))) ${display_options[$i]}"
        done
        echo ""
        echo -n "Choice [1-${num_items}]: "
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le $num_items ]]; then
            selected="${display_options[$((choice-1))]}"
        fi
    fi
    
    # Exit alternate screen
    tput rmcup
    
    if [[ -z "$selected" ]]; then
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
}

# ═══════════════════════════════════════════════════════════════
# EXPORT FUNCTIONS
# ═══════════════════════════════════════════════════════════════

export -f show_sidebar_picker
export SIDEBAR_PICKER_RESULT
