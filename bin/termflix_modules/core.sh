#!/usr/bin/env bash
#
# Termflix Core Module
# Color definitions, global variables, and basic utilities
#

# ============================================================
# COLOR DEFINITIONS - Charm/Charmbracelet Style Palette
# ============================================================
RED='\033[0;31m'
GREEN='\033[1;38;5;46m'       # Bright luminous green
YELLOW='\033[1;38;5;220m'     # Warm yellow/gold  
BLUE='\033[1;38;5;81m'        # Light blue
CYAN='\033[1;38;5;87m'        # Bright cyan
MAGENTA='\033[1;38;5;213m'    # Vibrant magenta/pink
PURPLE='\033[1;38;5;135m'     # Medium purple
PINK='\033[1;38;5;219m'       # Soft pink for secondary accents
BOLD='\033[1m'
RESET='\033[0m'

# Charm-style spinner configuration
CHARM_SPINNER_CHARS=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
CHARM_SPINNER_1_COLOR="$MAGENTA"   # First spinner - vibrant magenta
CHARM_SPINNER_2_COLOR="$CYAN"      # Second spinner - bright cyan

# ============================================================
# GLOBAL VARIABLES
# ============================================================
# Note: SCRIPT_DIR and TERMFLIX_SCRIPTS_DIR are set in main script

# ============================================================
# DEPENDENCY CHECKS
# ============================================================

# Check for jq (needed for API parsing)
check_jq() {
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Warning:${RESET} jq not found. Some search features may be limited."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "Install with: ${CYAN}brew install jq${RESET}"
        else
            echo "Install with: ${CYAN}sudo apt-get install jq${RESET} (Debian/Ubuntu) or ${CYAN}sudo yum install jq${RESET} (RHEL/CentOS)"
        fi
        echo
    fi
}

# Check for viu (optional, for displaying images)
check_viu() {
    if ! command -v viu &> /dev/null; then
        echo -e "${YELLOW}Note:${RESET} viu not found. Movie posters will not be displayed."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "Install with: ${CYAN}brew install viu${RESET} or ${CYAN}cargo install viu${RESET}"
        else
            echo "Install with: ${CYAN}cargo install viu${RESET} or ${CYAN}sudo apt-get install viu${RESET} (if available in repos)"
        fi
        echo
        return 1
    fi
    return 0
}

# ============================================================
# DIRECTORY INITIALIZATION
# ============================================================

# Get termflix config directory
get_termflix_config_dir() {
    echo "$HOME/.config/termflix"
}

# Get termflix cache directory
get_termflix_cache_dir() {
    echo "$HOME/.config/termflix/cache"
}

# Get termflix config file path
get_termflix_config_file() {
    echo "$(get_termflix_config_dir)/config"
}

# Initialize termflix directories
init_termflix_dirs() {
    local config_dir
    config_dir=$(get_termflix_config_dir)
    local cache_dir
    cache_dir=$(get_termflix_cache_dir)
    
    mkdir -p "$config_dir" 2>/dev/null || true
    mkdir -p "$cache_dir" 2>/dev/null || true
    mkdir -p "$cache_dir/tmdb" 2>/dev/null || true
    mkdir -p "$cache_dir/posters" 2>/dev/null || true
    mkdir -p "$cache_dir/viu_renders" 2>/dev/null || true
}

# ============================================================
# POSTER CLEANUP
# ============================================================

# Cleanup temporary poster images
cleanup_posters() {
    local temp_dir="${TMPDIR:-/tmp}/torrent_posters_$$"
    if [ -d "$temp_dir" ]; then
        rm -rf "$temp_dir" 2>/dev/null || true
    fi
}

# ============================================================
# PLAYER PREFERENCE
# ============================================================

# Get or set player preference
get_player_preference() {
    init_termflix_dirs
    local config_file
    config_file=$(get_termflix_config_file)
    
    if [ -f "$config_file" ]; then
        local player=$(grep "^PLAYER=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]')
        if [ -n "$player" ]; then
            echo "$player"
            return 0
        fi
    fi
    
    # Default to mpv if not set
    echo "mpv"
    return 0
}

set_player_preference() {
    local player="$1"
    init_termflix_dirs
    local config_file
    config_file=$(get_termflix_config_file)
    
    # Update or create config entry
    if [ -f "$config_file" ]; then
        # Update existing entry or add if not present
        if grep -q "^PLAYER=" "$config_file" 2>/dev/null; then
            sed -i.bak "s/^PLAYER=.*/PLAYER=$player/" "$config_file" 2>/dev/null || \
                sed -i "s/^PLAYER=.*/PLAYER=$player/" "$config_file" 2>/dev/null
        else
            echo "PLAYER=$player" >> "$config_file"
        fi
    else
        echo "PLAYER=$player" > "$config_file"
    fi
}
