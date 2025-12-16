#!/usr/bin/env bash
#
# Termflix Dependencies Module
# Dependency checking and initialization
#
# @version 1.0.0
# @updated 2025-12-14
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_DEPS_LOADED:-}" ]] && return 0
_TERMFLIX_DEPS_LOADED=1

# ═══════════════════════════════════════════════════════════════
# DEPENDENCY CHECKS
# ═══════════════════════════════════════════════════════════════

# Check for jq (JSON parsing)
check_jq() {
    if ! command -v jq &>/dev/null; then
        show_warning "jq not found. Some features may be limited."
        show_info "Install with: brew install jq"
        return 1
    fi
    return 0
}

# Check for viu (terminal image display)
check_viu() {
    if ! command -v viu &>/dev/null; then
        show_warning "viu not found. Poster display disabled."
        show_info "Install with: brew install viu"
        return 1
    fi
    return 0
}

# Check for curl (HTTP requests)
check_curl() {
    if ! command -v curl &>/dev/null; then
        show_error "curl is required but not found."
        return 1
    fi
    return 0
}

# Check for player (mpv or vlc)
check_player() {
    if command -v mpv &>/dev/null; then
        echo "mpv"
        return 0
    elif command -v vlc &>/dev/null; then
        echo "vlc"
        return 0
    else
        show_error "No media player found. Install mpv or vlc."
        return 1
    fi
}

# Check for torrent client (peerflix or transmission-cli)
check_torrent_client() {
    if command -v peerflix &>/dev/null; then
        echo "peerflix"
        return 0
    elif command -v transmission-cli &>/dev/null; then
        echo "transmission-cli"
        return 0
    elif command -v webtorrent &>/dev/null; then
        echo "webtorrent"
        return 0
    else
        show_error "No torrent client found. Install peerflix, transmission-cli, or webtorrent."
        return 1
    fi
}

# Check for Python3
check_python() {
    if ! command -v python3 &>/dev/null; then
        show_error "python3 is required but not found."
        return 1
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════
# DEPENDENCY SUMMARY
# ═══════════════════════════════════════════════════════════════

# Check all dependencies and report status
check_all_deps() {
    local has_errors=0
    
    echo -e "${C_GLOW}Checking dependencies...${RESET}"
    echo ""
    
    # Required
    if check_curl; then
        echo -e "  ${C_SUCCESS}✓${RESET} curl"
    else
        has_errors=1
    fi
    
    if check_python; then
        echo -e "  ${C_SUCCESS}✓${RESET} python3"
    else
        has_errors=1
    fi
    
    local player=$(check_player 2>/dev/null)
    if [[ -n "$player" ]]; then
        echo -e "  ${C_SUCCESS}✓${RESET} $player (media player)"
    else
        has_errors=1
    fi
    
    local torrent_client=$(check_torrent_client 2>/dev/null)
    if [[ -n "$torrent_client" ]]; then
        echo -e "  ${C_SUCCESS}✓${RESET} $torrent_client (torrent client)"
    else
        has_errors=1
    fi
    
    # Optional
    if check_jq 2>/dev/null; then
        echo -e "  ${C_SUCCESS}✓${RESET} jq (optional)"
    else
        echo -e "  ${C_WARNING}○${RESET} jq (optional - not installed)"
    fi
    
    if check_viu 2>/dev/null; then
        echo -e "  ${C_SUCCESS}✓${RESET} viu (optional - poster display)"
    else
        echo -e "  ${C_WARNING}○${RESET} viu (optional - not installed)"
    fi
    
    echo ""
    
    if [[ $has_errors -eq 0 ]]; then
        echo -e "${C_SUCCESS}All required dependencies satisfied!${RESET}"
        return 0
    else
        echo -e "${C_ERROR}Some required dependencies are missing.${RESET}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════

# Initialize termflix directories
init_termflix_dirs() {
    local config_dir="${HOME}/.config/termflix"
    local cache_dir="${config_dir}/cache"
    
    mkdir -p "$config_dir" 2>/dev/null
    mkdir -p "$cache_dir" 2>/dev/null
    mkdir -p "${cache_dir}/tmdb" 2>/dev/null
    mkdir -p "${cache_dir}/viu_renders" 2>/dev/null
    mkdir -p "${cache_dir}/posters" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════
# EXPORT FUNCTIONS
# ═══════════════════════════════════════════════════════════════

export -f check_jq check_viu check_curl check_player check_torrent_client
export -f check_python check_all_deps init_termflix_dirs
