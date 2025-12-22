#!/usr/bin/env bash
#
# Termflix Theme Loader
# Parses CSS-like theme files and exports ANSI color variables
#
# Features:
#   - True-color (24-bit) support for modern terminals
#   - 256-color fallback for compatibility
#   - Auto-reload when theme file changes
#   - CSS-like :root { --var: #hex; } syntax
#
# @version 1.0.0
# @updated 2025-12-15
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_THEME_LOADED:-}" ]] && return 0
_TERMFLIX_THEME_LOADED=1

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

# Read theme from config file if TERMFLIX_THEME not already set via environment
if [[ -z "${TERMFLIX_THEME:-}" ]]; then
    # Try to read THEME from config file directly (avoid circular dependency with config.sh)
    _config_file="${HOME}/.config/termflix/config"
    if [[ -f "$_config_file" ]]; then
        _theme_from_config=$(grep "^THEME=" "$_config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]"'"'"'')
        [[ -n "$_theme_from_config" ]] && TERMFLIX_THEME="$_theme_from_config"
    fi
fi
export TERMFLIX_THEME="${TERMFLIX_THEME:-charm}"
TERMFLIX_THEME_DIR="${TERMFLIX_THEME_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../themes}"
TERMFLIX_USER_THEME_DIR="${HOME}/.config/termflix/themes"
TERMFLIX_THEME_CACHE=""
TERMFLIX_THEME_MTIME=""

# ═══════════════════════════════════════════════════════════════
# TERMINAL CAPABILITY DETECTION
# ═══════════════════════════════════════════════════════════════

# Check if terminal supports true color (24-bit)
supports_truecolor() {
    # Kitty, iTerm2, modern terminals
    [[ "$COLORTERM" == "truecolor" || "$COLORTERM" == "24bit" ]] && return 0
    [[ "$TERM" == "xterm-kitty" ]] && return 0
    [[ -n "$ITERM_SESSION_ID" ]] && return 0
    [[ "$TERM_PROGRAM" == "iTerm.app" ]] && return 0
    [[ "$TERM_PROGRAM" == "Hyper" ]] && return 0
    [[ "$TERM_PROGRAM" == "vscode" ]] && return 0
    [[ "$WT_SESSION" ]] && return 0  # Windows Terminal
    return 1
}

# ═══════════════════════════════════════════════════════════════
# HEX TO ANSI CONVERSION
# ═══════════════════════════════════════════════════════════════

# Convert hex to RGB components
hex_to_rgb() {
    local hex="${1#\#}"
    printf "%d %d %d" "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# Convert hex to true-color (24-bit) ANSI escape
hex_to_truecolor() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
}

# Convert hex to true-color background ANSI escape  
hex_to_truecolor_bg() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    printf '\033[48;2;%d;%d;%dm' "$r" "$g" "$b"
}

# Convert hex to closest 256-color ANSI code
hex_to_256() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    
    # 6x6x6 color cube starts at index 16
    # Each component maps to 0-5
    local ri=$(( (r * 5 + 127) / 255 ))
    local gi=$(( (g * 5 + 127) / 255 ))
    local bi=$(( (b * 5 + 127) / 255 ))
    
    # Check if grayscale is closer
    local gray_avg=$(( (r + g + b) / 3 ))
    local gray_idx=$(( (gray_avg - 8) / 10 ))
    [[ $gray_idx -lt 0 ]] && gray_idx=0
    [[ $gray_idx -gt 23 ]] && gray_idx=23
    
    # Calculate color cube index
    local cube_idx=$(( 16 + 36*ri + 6*gi + bi ))
    
    # Use grayscale if colors are close enough
    local r_diff=$(( r - g )); r_diff=${r_diff#-}
    local g_diff=$(( g - b )); g_diff=${g_diff#-}
    
    if [[ $r_diff -lt 10 && $g_diff -lt 10 ]]; then
        # Grayscale ramp (232-255)
        printf '\033[38;5;%dm' "$((232 + gray_idx))"
    else
        printf '\033[38;5;%dm' "$cube_idx"
    fi
}

# Smart hex to ANSI - uses true color if supported, else 256
hex_to_ansi() {
    local hex="$1"
    if supports_truecolor; then
        hex_to_truecolor "$hex"
    else
        hex_to_256 "$hex"
    fi
}

# ═══════════════════════════════════════════════════════════════
# CSS PARSER
# ═══════════════════════════════════════════════════════════════

# Find theme file (user themes take priority)
find_theme_file() {
    local theme_name="$1"
    
    # Try user themes first
    if [[ -f "${TERMFLIX_USER_THEME_DIR}/${theme_name}.css" ]]; then
        echo "${TERMFLIX_USER_THEME_DIR}/${theme_name}.css"
        return 0
    fi
    
    # Try bundled themes
    if [[ -f "${TERMFLIX_THEME_DIR}/${theme_name}.css" ]]; then
        echo "${TERMFLIX_THEME_DIR}/${theme_name}.css"
        return 0
    fi
    
    # Fallback to default
    if [[ -f "${TERMFLIX_THEME_DIR}/default.css" ]]; then
        echo "${TERMFLIX_THEME_DIR}/default.css"
        return 0
    fi
    
    return 1
}

# Parse CSS theme file and extract variables
parse_theme_css() {
    local css_file="$1"
    
    [[ ! -f "$css_file" ]] && return 1
    
    # Read entire file
    local content
    content=$(cat "$css_file")
    
    # Extract variables from :root { } block
    # Format: --name: #hex;
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*/\* ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Match --variable: #hexvalue;
        if [[ "$line" =~ --([a-zA-Z0-9_-]+):[[:space:]]*(\#[0-9A-Fa-f]{6})[[:space:]]*\; ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local hex_value="${BASH_REMATCH[2]}"
            
            # Convert CSS variable name to bash variable name
            # --glow -> THEME_GLOW, --bg-selection -> THEME_BG_SELECTION
            local bash_name=$(echo "$var_name" | tr '[:lower:]-' '[:upper:]_')
            
            # Store hex value for later use (e.g., by FZF) - EXPORT for subprocesses
            eval "export THEME_HEX_${bash_name}=\"${hex_value}\""
            
            # Convert to ANSI and store
            local ansi_code
            ansi_code=$(hex_to_ansi "$hex_value")
            eval "export THEME_${bash_name}=\"\${ansi_code}\""
        fi
    done <<< "$content"
}

# ═══════════════════════════════════════════════════════════════
# THEME LOADING
# ═══════════════════════════════════════════════════════════════

# Load theme and set color variables
load_theme() {
    local theme_name="${1:-$TERMFLIX_THEME}"
    local theme_file
    
    theme_file=$(find_theme_file "$theme_name")
    
    if [[ -z "$theme_file" || ! -f "$theme_file" ]]; then
        echo "Warning: Theme '$theme_name' not found, using defaults" >&2
        return 1
    fi
    
    # Store for auto-reload
    TERMFLIX_THEME_CACHE="$theme_file"
    TERMFLIX_THEME_MTIME=$(stat -f%m "$theme_file" 2>/dev/null || stat -c%Y "$theme_file" 2>/dev/null)
    
    # Parse the CSS
    parse_theme_css "$theme_file"
    
    # Export legacy color variables for backward compatibility
    export_legacy_colors
}

# Check if theme file changed and reload
check_theme_reload() {
    [[ -z "$TERMFLIX_THEME_CACHE" ]] && return 1
    [[ ! -f "$TERMFLIX_THEME_CACHE" ]] && return 1
    
    local current_mtime
    current_mtime=$(stat -f%m "$TERMFLIX_THEME_CACHE" 2>/dev/null || stat -c%Y "$TERMFLIX_THEME_CACHE" 2>/dev/null)
    
    if [[ "$current_mtime" != "$TERMFLIX_THEME_MTIME" ]]; then
        load_theme "$TERMFLIX_THEME"
        return 0
    fi
    
    return 1
}

# Export legacy color variable names for backward compatibility
export_legacy_colors() {
    # Map new theme vars to old color names
    C_GLOW="${THEME_GLOW:-$'\033[38;5;206m'}"
    C_PURPLE="${THEME_PURPLE:-$'\033[38;5;135m'}"
    C_LAVENDER="${THEME_LAVENDER:-$'\033[38;5;183m'}"
    C_SUCCESS="${THEME_SUCCESS:-$'\033[38;5;86m'}"
    C_ERROR="${THEME_ERROR:-$'\033[38;5;197m'}"
    C_WARNING="${THEME_WARNING:-$'\033[38;5;221m'}"
    C_INFO="${THEME_INFO:-$'\033[38;5;86m'}"
    
    C_SUBTLE="${THEME_FG_MUTED:-$'\033[38;5;248m'}"
    C_MUTED="${THEME_FG_SUBTLE:-$'\033[38;5;243m'}"
    C_CONTRAST="${THEME_FG:-$'\033[38;5;15m'}"
    C_SURFACE="${THEME_BG_SURFACE:-$'\033[38;5;236m'}"
    C_CHARCOAL="${THEME_BG:-$'\033[38;5;236m'}"
    
    # Source colors
    C_YTS="${THEME_YTS:-$'\033[38;5;86m'}"
    C_TPB="${THEME_TPB:-$'\033[38;5;221m'}"
    C_1337X="${THEME_X1337:-$'\033[38;5;206m'}"
    C_EZTV="${THEME_EZTV:-$'\033[38;5;183m'}"
    
    # Extra
    C_PINK="${THEME_GLOW:-$'\033[38;5;206m'}"
    C_ORANGE="${THEME_WARNING:-$'\033[38;5;209m'}"
    C_GRAY="${THEME_FG_MUTED:-$'\033[38;5;245m'}"
    
    # Backward compat aliases
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
}

# ═══════════════════════════════════════════════════════════════
# FZF COLOR STRING GENERATOR
# ═══════════════════════════════════════════════════════════════

# Generate FZF --color string from theme
get_fzf_colors() {
    local fg="${THEME_HEX_FG:-#F8F8F2}"
    local bg="${THEME_HEX_BG:-}"
    local hl="${THEME_HEX_GLOW:-#E879F9}"
    local sel_bg="${THEME_HEX_BG_SELECTION:-#44475A}"
    local info="${THEME_HEX_PURPLE:-#8B5CF6}"
    local prompt="${THEME_HEX_SUCCESS:-#5EEAD4}"
    local pointer="${THEME_HEX_GLOW:-#E879F9}"
    local marker="${THEME_HEX_GLOW:-#E879F9}"
    local spinner="${THEME_HEX_GLOW:-#E879F9}"
    local header="${THEME_HEX_PURPLE:-#8B5CF6}"
    
    # Build color string (use -1 for transparent bg)
    echo "fg:${fg},bg:-1,hl:${hl},fg+:#ffffff,bg+:${sel_bg},hl+:${hl},info:${info},prompt:${prompt},pointer:${pointer},marker:${marker},spinner:${spinner},header:${header}"
}

# ═══════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════

# Auto-load theme on source
load_theme "$TERMFLIX_THEME"

# Export functions
export -f hex_to_ansi hex_to_truecolor hex_to_256 supports_truecolor
export -f load_theme check_theme_reload get_fzf_colors
