#!/usr/bin/env bash
#
# Termflix Image Display Module
# Universal image display helpers that detect and use the best available method
#
# Features:
#   - Auto-detects terminal capabilities (kitty, viu, chafa)
#   - Graceful fallback to text placeholder
#   - Supports custom width/height parameters
#
# @version 1.0.0
# @created 2025-12-17
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_IMAGE_DISPLAY_LOADED:-}" ]] && return 0
_TERMFLIX_IMAGE_DISPLAY_LOADED=1

# ═══════════════════════════════════════════════════════════════
# UNIVERSAL IMAGE DISPLAY
# ═══════════════════════════════════════════════════════════════

# Display image using best available method
# Arguments:
#   $1 - Image path (required)
#   $2 - Width in characters (optional, default: 40)
#   $3 - Height in characters (optional, default: 30)
# Returns:
#   0 - Success
#   1 - Image file not found or display failed
display_image() {
    local image_path="$1"
    local width="${2:-40}"
    local height="${3:-30}"
    
    # Validate image path
    if [[ ! -f "$image_path" ]]; then
        echo -e "\n[POSTER]\n"
        return 1
    fi
    
    # Detect best display method and render
    if [[ "$TERM" == "xterm-kitty" ]] && command -v kitten &> /dev/null; then
        # Kitty terminal with icat support
        kitten icat --align left --width "$width" "$image_path" 2>/dev/null
        return $?
    elif command -v viu &> /dev/null; then
        # VIU - Unicode-based image viewer
        viu -w "$width" "$image_path" 2>/dev/null
        return $?
    elif command -v chafa &> /dev/null; then
        # Chafa - Block graphics fallback
        TERM=xterm-256color chafa --symbols=block --size="${width}x${height}" "$image_path" 2>/dev/null
        return $?
    else
        # No display method available - show placeholder
        echo -e "\n[POSTER]\n"
        return 1
    fi
}

# Clear kitty inline images (no-op for other terminals)
# This is useful to prevent image artifacts when switching screens
# Returns:
#   0 - Always succeeds (no-op on non-kitty terminals)
clear_images() {
    if [[ "$TERM" == "xterm-kitty" ]] && command -v kitten &> /dev/null; then
        kitten icat --clear 2>/dev/null
    fi
    return 0
}

# Export functions for use in subshells
export -f display_image
export -f clear_images
