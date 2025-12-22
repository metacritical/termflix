#!/usr/bin/env bash
#
# Termflix Colors Module
# CSS-based theming with true-color support
#
# @version 2.0.0
# @updated 2025-12-15
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_COLORS_LOADED:-}" ]] && return 0
_TERMFLIX_COLORS_LOADED=1

# ═══════════════════════════════════════════════════════════════
# THEME LOADER
# ═══════════════════════════════════════════════════════════════

# Source theme loader first - this sets all color variables from CSS
COLORS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${COLORS_DIR}/theme.sh" ]]; then
    source "${COLORS_DIR}/theme.sh"
fi

# ═══════════════════════════════════════════════════════════════
# PRIMARY COLORS (Charmbracelet-inspired 256-color palette)
# ═══════════════════════════════════════════════════════════════
#
# USAGE GUIDE:
#   C_GLOW      → Selection highlights, focused items, pointers (➤)
#   C_SUBTLE    → Secondary/helper text, disabled labels
#   C_MUTED     → Disabled elements, less important info
#   C_SURFACE   → Light backgrounds, surfaces
#   C_CHARCOAL  → Dark borders, separators
#   C_CONTRAST  → Strong/primary text on dark backgrounds
#   C_ERROR     → Error messages, failure indicators (✗)
#   C_SUCCESS   → Success messages, positive indicators (✓)
#   C_WARNING   → Warnings, caution indicators (⚠)
#   C_INFO      → Informational messages (ℹ)
#   C_PURPLE    → Box borders, decorative elements
#   C_PINK      → Accents, highlights
#   C_ORANGE    → Icons, magnet symbols (🧲)
#   C_GRAY      → Muted dividers, horizontal rules
#
# ═══════════════════════════════════════════════════════════════

C_GLOW=$'\033[38;5;206m'       # Hot pink/magenta (#E879F9) - selection
C_SUBTLE=$'\033[38;5;248m'     # Light gray - secondary text
C_MUTED=$'\033[38;5;243m'      # Muted gray - disabled elements
C_SURFACE=$'\033[38;5;255m'    # Near-white - surfaces
C_CHARCOAL=$'\033[38;5;236m'   # Dark charcoal - subtle borders
C_CONTRAST=$'\033[38;5;15m'    # Pure white - primary text
C_ERROR=$'\033[38;5;197m'      # Hot coral red (#FF5555) - errors
C_SUCCESS=$'\033[38;5;86m'     # Bright cyan/aqua (#5EEAD4) - success ✓
C_WARNING=$'\033[38;5;221m'    # Warm gold - warnings
C_INFO=$'\033[38;5;86m'        # Cyan/aqua (#5EEAD4) - info
C_PURPLE=$'\033[38;5;135m'     # Vibrant purple (#8B5CF6) - borders
C_PINK=$'\033[38;5;212m'       # Soft pink (#F5A9B8) - secondary accents
C_ORANGE=$'\033[38;5;209m'     # Coral orange - icons
C_GRAY=$'\033[38;5;245m'       # Gray - dividers


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
# SOURCE-SPECIFIC COLORS (Charm-inspired)
# ═══════════════════════════════════════════════════════════════

C_YTS=$'\033[38;5;86m'         # Cyan/aqua (#5EEAD4) - matches Charm success
C_TPB=$'\033[38;5;221m'        # Warm gold - warnings/attention
C_1337X=$'\033[38;5;206m'      # Hot pink (#E879F9) - matches Charm brand
C_EZTV=$'\033[38;5;183m'       # Lavender (#C4B5FD) - subtle accent


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
ORANGE="${C_ORANGE}"
GRAY="${C_GRAY}"

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
