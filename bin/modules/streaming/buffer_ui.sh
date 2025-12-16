#!/usr/bin/env bash
#
# Termflix Buffer UI Module
# Reusable progress bar and buffering status display
#

# Source colors if not already loaded
if [[ -z "$C_RESET" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [[ -f "${SCRIPT_DIR}/../core/colors.sh" ]] && source "${SCRIPT_DIR}/../core/colors.sh"
fi

# Draw a progress bar
# Usage: draw_buffer_bar <percent> <width>
# Returns: Progress bar string like "🟩🟩🟩⬜⬜⬜"
draw_buffer_bar() {
    local percent="${1:-0}"
    local width="${2:-20}"
    
    # Ensure percent is integer
    percent=$(echo "$percent" | cut -d. -f1)
    [[ -z "$percent" ]] && percent=0
    [[ "$percent" -gt 100 ]] && percent=100
    [[ "$percent" -lt 0 ]] && percent=0
    
    local filled=$((percent * width / 100))
    [[ "$filled" -gt "$width" ]] && filled=$width
    
    local bar=""
    local i=0
    while [[ $i -lt $filled ]]; do
        bar="${bar}🟩"
        ((i++))
    done
    while [[ $i -lt $width ]]; do
        bar="${bar}⬜"
        ((i++))
    done
    
    echo "$bar"
}

# Draw a colored line progress bar (like image 2)
# Uses ━ character with colors
# Usage: draw_line_bar <percent> <width>
draw_line_bar() {
    local percent="${1:-0}"
    local width="${2:-40}"
    
    percent=$(echo "$percent" | cut -d. -f1)
    [[ -z "$percent" ]] && percent=0
    [[ "$percent" -gt 100 ]] && percent=100
    
    local filled=$((percent * width / 100))
    [[ "$filled" -gt "$width" ]] && filled=$width
    
    local bar=""
    local i=0
    
    # Filled portion (magenta/purple gradient)
    while [[ $i -lt $filled ]]; do
        bar="${bar}\033[38;5;129m━\033[0m"
        ((i++))
    done
    # Unfilled portion (gray)
    while [[ $i -lt $width ]]; do
        bar="${bar}\033[38;5;240m━\033[0m"
        ((i++))
    done
    
    echo -e "$bar"
}

# Format download stats
# Usage: format_download_stats <bytes_per_sec> <peers_connected> <peers_total>
format_download_stats() {
    local speed="$1"
    local peers_conn="${2:-0}"
    local peers_total="${3:-0}"
    
    local speed_display=""
    if [[ "$speed" -gt 1048576 ]]; then
        speed_display="$(echo "scale=1; $speed / 1048576" | bc 2>/dev/null || echo "$((speed / 1048576))") MB/s"
    elif [[ "$speed" -gt 1024 ]]; then
        speed_display="$(echo "scale=1; $speed / 1024" | bc 2>/dev/null || echo "$((speed / 1024))") KB/s"
    elif [[ "$speed" -gt 0 ]]; then
        speed_display="${speed} B/s"
    fi
    
    local stats=""
    [[ -n "$speed_display" ]] && stats="Down: ${speed_display}"
    [[ "$peers_total" -gt 0 ]] && stats="${stats}  S/L: ${peers_conn}/${peers_total}"
    
    echo "$stats"
}

# Display full buffering status line
# Usage: render_buffer_status <percent> <speed> <peers_conn> <peers_total> [<size_mb>]
render_buffer_status() {
    local percent="${1:-0}"
    local speed="${2:-0}"
    local peers_conn="${3:-0}"
    local peers_total="${4:-0}"
    local size_mb="${5:-}"
    
    local bar=$(draw_line_bar "$percent" 30)
    local stats=$(format_download_stats "$speed" "$peers_conn" "$peers_total")
    
    local size_display=""
    [[ -n "$size_mb" ]] && size_display="Size: ${size_mb} MB"
    
    echo -e "${bar}  ${percent}%"
    [[ -n "$stats" ]] && echo -e "${stats}"
    [[ -n "$size_display" ]] && echo -e "${size_display}"
}

# Export functions
export -f draw_buffer_bar draw_line_bar format_download_stats render_buffer_status
