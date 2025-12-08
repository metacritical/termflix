#!/usr/bin/env bash
#
# Termflix UI Module
# Spinners, progress bars, help screen, and UI utilities
#

# Charm-style dual spinner function for waiting/searching
# Uses magenta + cyan spinners rotating in opposite directions
show_spinner() {
    local pid=$1
    local message="${2:-Processing...}"
    local chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local idx1=0
    local idx2=0
    local len=${#chars[@]}
    while kill -0 "$pid" 2>/dev/null; do
        # Dual spinner: magenta goes backward, cyan goes forward
        printf "\r\033[1;38;5;213m%s\033[1;38;5;87m%s\033[0m %s" "${chars[$idx1]}" "${chars[$idx2]}" "$message"
        idx1=$(( (idx1 - 1 + len) % len ))
        idx2=$(( (idx2 + 1) % len ))
        sleep 0.1
    done
    printf "\r\033[1;38;5;46m✓\033[0m %s\n" "$message"
}

# Progress bar with emojis
show_progress() {
    local current=$1
    local total=$2
    local label="${3:-Progress}"
    local width=20
    
    # Ensure current doesn't exceed total
    if [ "$current" -gt "$total" ]; then
        current=$total
    fi
    
    local filled=$((current * width / total))
    if [ "$filled" -gt "$width" ]; then
        filled=$width
    fi
    local empty=$((width - filled))
    
    # Build progress bar
    local bar=""
    local i=0
    while [ $i -lt $filled ]; do
        bar="${bar}🟩"
        i=$((i + 1))
    done
    while [ $i -lt $width ]; do
        bar="${bar}⬜"
        i=$((i + 1))
    done
    
    local percent=$((current * 100 / total))
    if [ "$percent" -gt 100 ]; then
        percent=100
    fi
    printf "\r${MAGENTA}%s:${RESET} %s %d%% (%d/%d) " "$label" "$bar" "$percent" "$current" "$total"
}

# Show help screen
show_help() {
    cat << 'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          TERMFLIX - Movie Streaming
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

USAGE:
  termflix [command] [options]
  termflix <magnet_link|torrent_file>

COMMANDS:
  search <query>     Search for movies/TV shows
  latest             Browse latest movies catalog
  trending           Browse trending movies
  popular            Browse popular movies  
  genre <name>       Browse by genre (action, comedy, etc.)
  
STREAMING:
  <magnet_link>      Stream from magnet link
  <torrent_file>     Stream from torrent file
  
OPTIONS:
  --player <name>    Set media player (mpv, vlc, iina)
  --quality <res>    Set preferred quality (720p, 1080p, 4K)
  --clear            Clear cache and re-fetch
  --help             Show this help screen
  
EXAMPLES:
  termflix search inception
  termflix latest
  termflix genre action
  termflix magnet:?xt=urn:btih:...
  
NAVIGATION:
  ↑/↓ or j/k         Navigate catalog
  Enter              Select item
  Page Up/Down       Navigate pages
  q                  Quit/Back
  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}
