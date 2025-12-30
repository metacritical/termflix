#!/usr/bin/env bash
#
# Termflix Logo Module
# Crush-inspired ASCII art logo for FZF header
#
# @version 1.0.0
# @updated 2025-12-15
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_LOGO_LOADED:-}" ]] && return 0
_TERMFLIX_LOGO_LOADED=1

# ═══════════════════════════════════════════════════════════════
# LOGO DATA
# ═══════════════════════════════════════════════════════════════

# Crush-inspired pixel-style logo for Termflix
# Uses true-color gradient from pink to purple

get_termflix_logo() {
    local use_color="${1:-true}"
    local icon="${TERMFLIX_LOGO_ICON-🍿}"
    
    # Colors for gradient effect (pink → purple)
    local P1="${THEME_GLOW:-\033[38;2;232;121;249m}"         # Hot pink / theme glow
    local P2="${THEME_LAVENDER:-\033[38;2;192;132;252m}"     # Light purple / theme lavender
    local P3="${THEME_PURPLE:-\033[38;2;139;92;246m}"        # Purple / theme purple
    local P4="${THEME_BORDER:-${THEME_PURPLE:-\033[38;2;124;58;237m}}"  # Deep accent / border
    local R='\033[0m'
    
    if [[ "$use_color" != "true" ]]; then
        P1="" P2="" P3="" P4="" R=""
    fi
    
    # Compact pixel-art style logo (fits in header)
    # "TERMFLIX" in chunky block letters with gradient
    cat << EOF
${icon}
${P1}▀█▀${P2}█▀▀${P1}█▀█${P2}█▄█${P3}█▀▀${P4}█  ${P3}█${P4}▀█${R}
${P1} █ ${P2}██▄${P1}█▀▄${P2}█ █${P3}█▀ ${P4}█▄▄${P3}█${P4}▀▄${R}
EOF
}

# Single-line compact logo for FZF header
get_termflix_logo_inline() {
    local P1="${THEME_GLOW:-\033[38;2;232;121;249m}"     # Glow
    local P2="${THEME_PURPLE:-\033[38;2;139;92;246m}"    # Purple
    local C="${THEME_INFO:-\033[38;2;94;234;212m}"       # Cyan/info
    local R='\033[0m'
    
    local icon="${TERMFLIX_LOGO_ICON-🍿}"
    echo -e "${icon} ${P2}term${P1}flix${R}${C}_${R}"
}

# Fancy header with logo and version
get_termflix_header() {
    local version="${1:-1.0.0}"
    local icon="${TERMFLIX_LOGO_ICON-🍿}"
    
    local P1="${THEME_GLOW:-\033[38;2;232;121;249m}"     # Glow
    local P2="${THEME_PURPLE:-\033[38;2;139;92;246m}"    # Purple
    local C="${THEME_INFO:-\033[38;2;94;234;212m}"       # Cyan/info
    local M="${THEME_FG_MUTED:-\033[38;2;107;114;128m}"  # Muted
    local I='\033[3m'                   # Italic
    local R='\033[0m'
    
    # Charm-style: italic prefix, bold name, version
    echo -e "${I}${M}charm™${R} ${icon} ${P1}TERM${P2}FLIX${R}™ ${M}v${version}${R}"
}

# Block-art logo for splash screen (larger)
get_termflix_logo_full() {
    local P1='\033[38;2;232;121;249m'  # Hot pink #E879F9
    local P2='\033[38;2;192;132;252m'  # Light purple #C084FC
    local P3='\033[38;2;139;92;246m'   # Purple #8B5CF6
    local DIM='\033[2m'
    local R='\033[0m'
    
    cat << 'LOGO'
                                                            
  ████████╗███████╗██████╗ ███╗   ███╗███████╗██╗     ██╗██╗  ██╗
  ╚══██╔══╝██╔════╝██╔══██╗████╗ ████║██╔════╝██║     ██║╚██╗██╔╝
     ██║   █████╗  ██████╔╝██╔████╔██║█████╗  ██║     ██║ ╚███╔╝ 
     ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║██╔══╝  ██║     ██║ ██╔██╗ 
     ██║   ███████╗██║  ██║██║ ╚═╝ ██║██║     ███████╗██║██╔╝ ██╗
     ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝     ╚══════╝╚═╝╚═╝  ╚═╝
                                                            
LOGO
}

# Compact 1-line version for terminals
get_termflix_logo_compact() {
    local P="${THEME_GLOW:-\033[38;2;232;121;249m}"  # Glow
    local C="${THEME_INFO:-\033[38;2;94;234;212m}"   # Info
    local R='\033[0m'
    
    local icon="${TERMFLIX_LOGO_ICON-🍿}"
    echo -e "${icon} ${P}termflix${R} ${C}▸${R}"
}

# Export functions
export -f get_termflix_logo get_termflix_logo_inline get_termflix_header
export -f get_termflix_logo_full get_termflix_logo_compact
