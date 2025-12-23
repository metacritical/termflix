#!/usr/bin/env bash
#
# Termflix Status Module
# Status bar, spinners, and progress indicators
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_STATUS_LOADED:-}" ]] && return 0
_TERMFLIX_STATUS_LOADED=1

# ═══════════════════════════════════════════════════════════════
# SPINNERS
# ═══════════════════════════════════════════════════════════════

# Charmbracelet-style spinner characters
SPINNER_CHARS=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

# Show spinner while a process runs
# Usage: some_command & show_spinner $! "Loading..."
show_spinner() {
    local pid="$1"
    local message="${2:-Loading...}"
    local i=0
    
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${C_GLOW:-\033[38;5;212m}${SPINNER_CHARS[$i]}${RESET:-\033[0m} ${C_SUBTLE:-\033[38;5;245m}${message}${RESET:-\033[0m}"
        i=$(( (i + 1) % ${#SPINNER_CHARS[@]} ))
        sleep 0.1
    done
    printf "\r${C_SUCCESS:-\033[38;5;46m}✓${RESET:-\033[0m} ${message}                    \n"
}

# Show inline spinner (doesn't wait for process)
show_spinner_inline() {
    local message="$1"
    local i="${2:-0}"
    printf "\r${C_GLOW:-\033[38;5;212m}${SPINNER_CHARS[$i]}${RESET:-\033[0m} ${C_SUBTLE:-\033[38;5;245m}${message}${RESET:-\033[0m}"
}

# Clear spinner line
clear_spinner() {
    printf "\r%*s\r" "$(tput cols)" ""
}

# ═══════════════════════════════════════════════════════════════
# PROGRESS BARS
# ═══════════════════════════════════════════════════════════════

# Show progress bar with optional gradient and speed/ETA
# Usage: show_progress_bar 50 100 30 "1.2 MB/s" "3:24"
show_progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-30}"
    local speed="${4:-}"
    local eta="${5:-}"
    
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    # Gradient colors: magenta -> pink -> cyan
    local GRAD_START='\033[38;5;213m'  # Magenta
    local GRAD_MID='\033[38;5;219m'    # Pink
    local GRAD_END='\033[38;5;87m'     # Cyan
    
    printf "\r${C_PURPLE:-\033[38;5;135m}[${RESET:-\033[0m}"
    
    # Draw gradient bar
    local third=$((filled / 3))
    local remaining=$((filled - third * 2))
    [[ $third -gt 0 ]] && printf "${GRAD_START}%${third}s${RESET:-\033[0m}" | tr ' ' '█'
    [[ $third -gt 0 ]] && printf "${GRAD_MID}%${third}s${RESET:-\033[0m}" | tr ' ' '█'
    [[ $remaining -gt 0 ]] && printf "${GRAD_END}%${remaining}s${RESET:-\033[0m}" | tr ' ' '█'
    
    # Empty portion
    printf "${C_MUTED:-\033[38;5;241m}%${empty}s${RESET:-\033[0m}" | tr ' ' '░'
    printf "${C_PURPLE:-\033[38;5;135m}]${RESET:-\033[0m} ${C_SUBTLE:-\033[38;5;245m}%3d%%${RESET:-\033[0m}" "$percent"
    
    # Speed and ETA display
    if [[ -n "$speed" ]]; then
        printf " ${C_GLOW:-\033[38;5;212m}%s${RESET:-\033[0m}" "$speed"
        [[ -n "$eta" ]] && printf " • ${C_MUTED:-\033[38;5;241m}%s${RESET:-\033[0m}" "$eta"
    fi
}

# Complete progress bar with message
show_progress_complete() {
    local message="${1:-Done}"
    local width="${2:-30}"
    
    printf "\r${C_PURPLE:-\033[38;5;135m}[${RESET:-\033[0m}"
    printf "${C_SUCCESS:-\033[38;5;46m}%${width}s${RESET:-\033[0m}" | tr ' ' '█'
    printf "${C_PURPLE:-\033[38;5;135m}]${RESET:-\033[0m} ${C_SUCCESS:-\033[38;5;46m}${message}${RESET:-\033[0m}\n"
}

# ═══════════════════════════════════════════════════════════════
# STATUS BAR
# ═══════════════════════════════════════════════════════════════

# Render status bar at bottom of screen
render_status_bar() {
    local left_text="${1:-}"
    local center_text="${2:-}"
    local right_text="${3:-}"
    
    local term_lines=$(tput lines)
    local term_cols=$(tput cols)
    local status_row=$((term_lines - 1))
    
    # Save cursor position
    tput sc
    
    # Move to status bar row
    tput cup $status_row 0
    
    # Draw background
    echo -ne "\033[48;5;235m"  # Dark background
    printf "%-${term_cols}s" ""
    
    # Left section
    if [[ -n "$left_text" ]]; then
        tput cup $status_row 1
        echo -ne "${C_SUBTLE:-\033[38;5;245m}${left_text}${RESET:-\033[0m}"
    fi
    
    # Center section
    if [[ -n "$center_text" ]]; then
        local center_col=$(( (term_cols - ${#center_text}) / 2 ))
        tput cup $status_row $center_col
        echo -ne "${C_SUBTLE:-\033[38;5;245m}${center_text}${RESET:-\033[0m}"
    fi
    
    # Right section
    if [[ -n "$right_text" ]]; then
        local right_col=$((term_cols - ${#right_text} - 2))
        tput cup $status_row $right_col
        echo -ne "${C_MUTED:-\033[38;5;241m}${right_text}${RESET:-\033[0m}"
    fi
    
    # Reset background and restore cursor
    echo -ne "\033[0m"
    tput rc
}

# Render navigation hints in status bar with colored keys
render_nav_hints() {
    local term_lines=$(tput lines)
    local term_cols=$(tput cols)
    
    # Color definitions for key hints
    local KEY_PINK='\033[38;5;212m'     # Action keys (j/k)
    local KEY_GREEN='\033[38;5;46m'     # Confirm key (Enter)
    local KEY_GRAY='\033[38;5;241m'     # Exit key (q)
    local SEP='\033[38;5;245m'          # Separator (•)
    
    # Styled hints
    local hints="${KEY_PINK}j${RESET:-\033[0m}/${KEY_PINK}k${RESET:-\033[0m} ${SEP}move${RESET:-\033[0m}  ${SEP}•${RESET:-\033[0m}  ${KEY_GREEN}enter${RESET:-\033[0m} ${SEP}select${RESET:-\033[0m}  ${SEP}•${RESET:-\033[0m}  ${KEY_GRAY}q${RESET:-\033[0m} ${SEP}quit${RESET:-\033[0m}"
    
    # Calculate center position (account for ANSI codes in length)
    local visible_len=26  # Approximate visible length without ANSI
    local hints_col=$(( (term_cols - visible_len) / 2 ))
    
    tput cup $((term_lines - 1)) $hints_col
    echo -ne "\033[48;5;235m${hints}\033[0m"
}

# ═══════════════════════════════════════════════════════════════
# HEADER
# ═══════════════════════════════════════════════════════════════

# Render header bar at top of screen
render_header() {
    local title="${1:-Termflix}"
    local subtitle="${2:-}"
    
    local term_cols=$(tput cols)
    
    # Move to top
    tput cup 0 0
    
    # Draw title
    echo -ne "${C_GLOW:-\033[38;5;212m}${BOLD:-\033[1m}${title}${RESET:-\033[0m}"
    
    # Draw subtitle if provided
    if [[ -n "$subtitle" ]]; then
        echo -ne " ${C_SUBTLE:-\033[38;5;245m}${subtitle}${RESET:-\033[0m}"
    fi
    
    # Draw underline
    tput cup 1 0
    echo -ne "${C_PURPLE:-\033[38;5;135m}"
    printf '─%.0s' $(seq 1 $term_cols)
    echo -ne "${RESET:-\033[0m}"
}

# ═══════════════════════════════════════════════════════════════
# EXPORT FUNCTIONS
# ═══════════════════════════════════════════════════════════════

export -f show_spinner show_spinner_inline clear_spinner
export -f show_progress_bar show_progress_complete
export -f render_status_bar render_nav_hints render_header
