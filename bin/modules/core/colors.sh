#!/usr/bin/env bash
#
# Termflix Colors Module
# Charmbracelet-style color palette using 256-color ANSI
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_COLORS_LOADED:-}" ]] && return 0
_TERMFLIX_COLORS_LOADED=1

# ═══════════════════════════════════════════════════════════════
# PRIMARY COLORS (Charmbracelet-inspired)
# ═══════════════════════════════════════════════════════════════

C_GLOW=$'\033[38;5;212m'       # Vibrant pink (selection/highlight)
C_SUBTLE=$'\033[38;5;245m'     # Light gray (secondary text)
C_MUTED=$'\033[38;5;241m'      # Muted gray (disabled elements)
C_SURFACE=$'\033[38;5;249m'    # Light background
C_CHARCOAL=$'\033[38;5;235m'   # Dark gray (borders)
C_CONTRAST=$'\033[38;5;15m'    # White (strong text)
C_ERROR=$'\033[38;5;203m'      # Red (errors)
C_SUCCESS=$'\033[38;5;46m'     # Green (success)
C_WARNING=$'\033[38;5;220m'    # Yellow (warnings)
C_INFO=$'\033[38;5;81m'        # Cyan (info)
C_PURPLE=$'\033[38;5;135m'     # Purple (borders)
C_PINK=$'\033[38;5;219m'       # Soft pink (accents)

# ═══════════════════════════════════════════════════════════════
# TEXT STYLES
# ═══════════════════════════════════════════════════════════════

BOLD=$'\033[1m'
DIM=$'\033[2m'
ITALIC=$'\033[3m'
UNDERLINE=$'\033[4m'
BLINK=$'\033[5m'
REVERSE=$'\033[7m'
RESET=$'\033[0m'

# ═══════════════════════════════════════════════════════════════
# SOURCE-SPECIFIC COLORS
# ═══════════════════════════════════════════════════════════════

C_YTS=$'\033[38;5;46m'         # Bright green
C_TPB=$'\033[38;5;220m'        # Warm yellow
C_1337X=$'\033[38;5;213m'      # Vibrant magenta
C_EZTV=$'\033[38;5;81m'        # Light cyan

# ═══════════════════════════════════════════════════════════════
# BACKWARD COMPATIBILITY (old color names)
# ═══════════════════════════════════════════════════════════════

RED="${C_ERROR}"
GREEN="${C_SUCCESS}"
YELLOW="${C_WARNING}"
BLUE="${C_INFO}"
CYAN="${C_INFO}"
MAGENTA="${C_GLOW}"
PURPLE="${C_PURPLE}"
PINK="${C_PINK}"

# ═══════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Apply style to text
# Usage: styled "$C_GLOW$BOLD" "Hello World"
styled() {
    local style="$1"
    local text="$2"
    echo -e "${style}${text}${RESET}"
}

# Print styled text without newline
styled_n() {
    local style="$1"
    local text="$2"
    echo -ne "${style}${text}${RESET}"
}

# ═══════════════════════════════════════════════════════════════
# BOX DRAWING
# ═══════════════════════════════════════════════════════════════

# Draw top of box: ╭────────╮
box_top() {
    local width="${1:-40}"
    echo -e "${C_PURPLE}╭$(printf '─%.0s' $(seq 1 $width))╮${RESET}"
}

# Draw bottom of box: ╰────────╯
box_bottom() {
    local width="${1:-40}"
    echo -e "${C_PURPLE}╰$(printf '─%.0s' $(seq 1 $width))╯${RESET}"
}

# Draw box line: │ content │
box_line() {
    local content="$1"
    local width="${2:-40}"
    echo -e "${C_PURPLE}│${RESET}${content}${C_PURPLE}│${RESET}"
}

# Draw horizontal line: ─────────
hline() {
    local width="${1:-40}"
    local color="${2:-$C_PURPLE}"
    echo -e "${color}$(printf '─%.0s' $(seq 1 $width))${RESET}"
}

# Draw vertical divider at position
vline_at() {
    local row="$1"
    local col="$2"
    local color="${3:-$C_PURPLE}"
    tput cup "$row" "$col"
    echo -ne "${color}│${RESET}"
}

# ═══════════════════════════════════════════════════════════════
# SOURCE TAG FORMATTING
# ═══════════════════════════════════════════════════════════════

# Format source name with color
# Usage: format_source "YTS"
format_source() {
    local src="$1"
    case "$src" in
        YTS)   echo -ne "${C_YTS}[YTS]${RESET}" ;;
        TPB)   echo -ne "${C_TPB}[TPB]${RESET}" ;;
        1337x) echo -ne "${C_1337X}[1337x]${RESET}" ;;
        EZTV)  echo -ne "${C_EZTV}[EZTV]${RESET}" ;;
        *)     echo -ne "${C_SUBTLE}[$src]${RESET}" ;;
    esac
}

# Get color for source
get_source_color() {
    local src="$1"
    case "$src" in
        YTS)   echo "$C_YTS" ;;
        TPB)   echo "$C_TPB" ;;
        1337x) echo "$C_1337X" ;;
        EZTV)  echo "$C_EZTV" ;;
        *)     echo "$C_SUBTLE" ;;
    esac
}

# Format multiple sources from ^-delimited string
format_source_tags() {
    local sources="$1"
    IFS='^' read -ra src_arr <<< "$sources"
    for src in "${src_arr[@]}"; do
        format_source "$src"
        echo -n " "
    done
}

# ═══════════════════════════════════════════════════════════════
# EXPORT FUNCTIONS
# ═══════════════════════════════════════════════════════════════

export -f styled styled_n box_top box_bottom box_line hline vline_at
export -f format_source get_source_color format_source_tags
