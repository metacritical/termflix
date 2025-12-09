#!/usr/bin/env bash
#
# Termflix Help Module
# Help screen and usage information
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_HELP_LOADED:-}" ]] && return 0
_TERMFLIX_HELP_LOADED=1

# ═══════════════════════════════════════════════════════════════
# HELP SCREEN
# ═══════════════════════════════════════════════════════════════

# Show help screen
show_help() {
    # Ensure colors are available
    if [[ -z "$C_GLOW" ]]; then
        local C_GLOW='\033[38;5;212m'
        local C_SUBTLE='\033[38;5;245m'
        local C_MUTED='\033[38;5;241m'
        local C_ERROR='\033[38;5;203m'
        local C_SUCCESS='\033[38;5;46m'
        local C_WARNING='\033[38;5;220m'
        local C_INFO='\033[38;5;81m'
        local C_PURPLE='\033[38;5;135m'
        local C_PINK='\033[38;5;219m'
        local BOLD='\033[1m'
        local RESET='\033[0m'
    fi

    echo -e "${BOLD}${C_GLOW}Termflix${RESET} ${C_INFO}- Torrent Streaming Tool${RESET}"
    echo
    echo "Stream torrents directly to mpv or VLC player using peerflix."
    echo
    echo -e "${C_PINK}Usage:${RESET}"
    echo "  termflix                                    Show latest movies and shows (default)"
    echo "  termflix <magnet_link>"
    echo "  termflix <torrent_file>"
    echo "  termflix search <query>"
    echo "  termflix latest [movies|shows|all]"
    echo "  termflix trending [movies|shows|all]"
    echo "  termflix popular [movies|shows|all]"
    echo "  termflix catalog [genre]"
    echo
    echo -e "${C_PINK}Options:${RESET}"
    echo "  -h, --help          Show this help"
    echo "  -l, --list          List available files in torrent"
    echo "  -i, --index <num>   Select specific file by index"
    echo "  -q, --quality       Auto-select best quality"
    echo "  -s, --subtitles     Enable subtitle loading (auto-detected if available)"
    echo "  -v, --verbose       Verbose output"
    echo "      --debug         Show debug information (magnet links, etc.)"
    echo "      --clear         Clear catalog cache files"
    echo
    echo -e "${C_PINK}Commands:${RESET}"
    echo "  player <mpv|vlc>    Change default media player preference"
    echo
    echo -e "${C_PINK}Examples:${RESET}"
    echo "  termflix                                    # Show latest movies and shows"
    echo "  termflix \"magnet:?xt=urn:btih:...\""
    echo "  termflix movie.torrent"
    echo "  termflix search \"movie name\""
    echo "  termflix latest movies"
    echo "  termflix trending shows"
    echo "  termflix catalog action"
    echo
    echo -e "${C_PINK}Catalog Features:${RESET}"
    echo "  - Browse latest movies and TV shows (like Stremio)"
    echo "  - View trending and popular content"
    echo "  - Browse by genre/category"
    echo "  - Stremio-style posters and details"
}

# Export functions
export -f show_help
