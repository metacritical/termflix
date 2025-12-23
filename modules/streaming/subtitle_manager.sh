#!/usr/bin/env bash
#
# Termflix Subtitle Manager Module
# Subtitle detection and handling for torrent streaming
#
# Functions:
#   - has_subtitles(): Detects subtitle files in torrent
#   - find_subtitle_file(): Searches for subtitle files recursively
#   - prepare_subtitle_path(): Formats subtitle path for player
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_SUBTITLE_MANAGER_LOADED:-}" ]] && return 0
_TERMFLIX_SUBTITLE_MANAGER_LOADED=1

# ═══════════════════════════════════════════════════════════════
# SUBTITLE DETECTION
# ═══════════════════════════════════════════════════════════════

# Check if torrent has subtitle files and return info
# Args: $1 = magnet source or torrent path
# Returns: 0 if subtitles found, 1 if not found
has_subtitles() {
    local source="$1"
    
    # List files and check for subtitle extensions
    local file_list=$(peerflix "$source" --list 2>/dev/null || echo "")
    
    if [ -z "$file_list" ]; then
        return 1
    fi
    
    # Check for common subtitle file extensions and extract subtitle file names
    local subtitle_files=$(echo "$file_list" | grep -iE '\.(srt|vtt|ass|ssa|sub|idx)$' || echo "")
    
    if [ -n "$subtitle_files" ]; then
        # Count and list subtitle files found
        local sub_count=$(echo "$subtitle_files" | wc -l | tr -d ' ')
        echo -e "${GREEN}Subtitle found!${RESET} ($sub_count file(s))" >&2
        
        # Print subtitle file names (limit to first 3 to avoid clutter)
        echo "$subtitle_files" | head -3 | while IFS= read -r line; do
            if [ -n "$line" ]; then
                # Extract filename (usually the last part after spaces/tabs)
                # peerflix list format: "index  size  filename"
                local sub_file=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/[[:space:]]*$//' 2>/dev/null || echo "$line")
                if [ -n "$sub_file" ]; then
                    echo -e "  ${CYAN}→${RESET} $sub_file" >&2
                fi
            fi
        done
        
        local total_subs=$(echo "$subtitle_files" | wc -l | tr -d ' ')
        if [ "$total_subs" -gt 3 ]; then
            local remaining=$((total_subs - 3))
            echo -e "  ${CYAN}... and $remaining more${RESET}" >&2
        fi
        
        return 0
    fi
    
    return 1
}

# ═══════════════════════════════════════════════════════════════
# SUBTITLE SEARCH
# ═══════════════════════════════════════════════════════════════

# Find subtitle file in torrent directory (recursive search)
# Args: $1 = torrent path, $2 = max wait time (seconds)
# Returns: subtitle file path (stdout), exit code 0 if found
find_subtitle_file() {
    local torrent_path="$1"
    local max_wait="${2:-15}"
    
    if [ ! -d "$torrent_path" ]; then
        return 1
    fi
    
    local wait_count=0
    local subtitle_file=""
    
    echo -e "${YELLOW}Searching for subtitle files in torrent...${RESET}" >&2
    echo -e "${CYAN}Path:${RESET} $torrent_path" >&2
    echo "" >&2
    
    while [ $wait_count -lt $max_wait ]; do
        # List files periodically for debugging
        if [ $wait_count -eq 0 ] || [ $((wait_count % 3)) -eq 0 ]; then
            echo -e "${YELLOW}Files in torrent (attempt $((wait_count + 1))):${RESET}" >&2
            find "$torrent_path" -type f 2>/dev/null | head -10 | while IFS= read -r file; do
                if [ -n "$file" ]; then
                    local fname=$(basename "$file")
                    local fsize=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
                    local rel_path="${file#$torrent_path/}"
                    echo -e "  ${CYAN}→${RESET} $fname (${fsize} bytes) [${rel_path}]" >&2
                fi
            done
            echo "" >&2
        fi
        
        # Check for subtitle files (search recursively)
        local found_sub=$(find "$torrent_path" -type f -iname "*.srt" 2>/dev/null | head -1)
        if [ -z "$found_sub" ]; then
            found_sub=$(find "$torrent_path" -type f \( -iname "*.vtt" -o -iname "*.ass" -o -iname "*.ssa" \) 2>/dev/null | head -1)
        fi
        
        if [ -n "$found_sub" ] && [ -f "$found_sub" ] && [ -s "$found_sub" ]; then
            # File exists and has content - it's downloaded
            subtitle_file=$(realpath "$found_sub" 2>/dev/null || echo "$found_sub")
            local file_size=$(stat -f%z "$subtitle_file" 2>/dev/null || stat -c%s "$subtitle_file" 2>/dev/null || echo "0")
            
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" >&2
            echo -e "${GREEN}✓ SUBTITLE FOUND!${RESET}" >&2
            echo -e "  ${CYAN}File:${RESET} $(basename "$subtitle_file")" >&2
            echo -e "  ${CYAN}Location:${RESET} $subtitle_file" >&2
            echo -e "  ${CYAN}Size:${RESET} ${file_size} bytes" >&2
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" >&2
            
            echo "$subtitle_file"  # Output to stdout for capturing
            return 0
        fi
        
        sleep 1
        wait_count=$((wait_count + 1))
    done
    
    # Not found
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" >&2
    echo -e "${YELLOW}⚠ NO SUBTITLE FILE FOUND${RESET}" >&2
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" >&2
    echo -e "${YELLOW}Torrent path:${RESET} $torrent_path" >&2
    echo -e "${YELLOW}All files in torrent (recursive):${RESET}" >&2
    find "$torrent_path" -type f 2>/dev/null | while IFS= read -r file; do
        local rel_path="${file#$torrent_path/}"
        echo -e "  ${CYAN}→${RESET} $rel_path" >&2
    done
    echo "" >&2
    
    return 1
}

# ═══════════════════════════════════════════════════════════════
# SUBTITLE PATH PREPARATION
# ═══════════════════════════════════════════════════════════════

# Prepare subtitle path for player consumption
# Args: $1 = subtitle file path
# Returns: formatted path (escaped for player usage)
prepare_subtitle_path() {
    local subtitle_file="$1"
    
    if [ -z "$subtitle_file" ] || [ ! -f "$subtitle_file" ]; then
        return 1
    fi
    
    # Resolve to absolute path
    local abs_path=$(realpath "$subtitle_file" 2>/dev/null || echo "$subtitle_file")
    
    # Escape special characters for shell/player usage
    # Most players handle paths well, but escape quotes and backslashes
    local escaped_path=$(echo "$abs_path" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
    
    echo "$escaped_path"
    return 0
}

# ═══════════════════════════════════════════════════════════════
# EXPORT FUNCTIONS
# ═══════════════════════════════════════════════════════════════

export -f has_subtitles
export -f find_subtitle_file
export -f prepare_subtitle_path
