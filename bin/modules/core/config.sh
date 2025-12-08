#!/usr/bin/env bash
#
# Termflix Configuration Module
# Config file management and preferences
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_CONFIG_LOADED:-}" ]] && return 0
_TERMFLIX_CONFIG_LOADED=1

# ═══════════════════════════════════════════════════════════════
# CONFIG PATHS
# ═══════════════════════════════════════════════════════════════

# Get config directory
get_config_dir() {
    echo "${HOME}/.config/termflix"
}

# Get config file path
get_config_file() {
    echo "$(get_config_dir)/config"
}

# Get cache directory
get_cache_dir() {
    echo "$(get_config_dir)/cache"
}

# ═══════════════════════════════════════════════════════════════
# CONFIG READING
# ═══════════════════════════════════════════════════════════════

# Read a config value
# Usage: config_get "PLAYER" "mpv"
config_get() {
    local key="$1"
    local default="${2:-}"
    local config_file=$(get_config_file)
    
    if [[ -f "$config_file" ]]; then
        local value=$(grep "^${key}=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d '[:space:]')
        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
    fi
    
    echo "$default"
}

# ═══════════════════════════════════════════════════════════════
# CONFIG WRITING
# ═══════════════════════════════════════════════════════════════

# Write a config value
# Usage: config_set "PLAYER" "mpv"
config_set() {
    local key="$1"
    local value="$2"
    local config_file=$(get_config_file)
    local config_dir=$(get_config_dir)
    
    # Ensure directory exists
    mkdir -p "$config_dir" 2>/dev/null
    
    # Create file if doesn't exist
    touch "$config_file" 2>/dev/null
    
    # Remove existing key
    if grep -q "^${key}=" "$config_file" 2>/dev/null; then
        # macOS compatible sed
        sed -i '' "/^${key}=/d" "$config_file" 2>/dev/null || \
        sed -i "/^${key}=/d" "$config_file" 2>/dev/null
    fi
    
    # Add new key=value
    echo "${key}=${value}" >> "$config_file"
}

# ═══════════════════════════════════════════════════════════════
# SPECIFIC CONFIG GETTERS/SETTERS
# ═══════════════════════════════════════════════════════════════

# Get preferred player
get_player_preference() {
    local player=$(config_get "PLAYER" "")
    
    # Validate player exists
    if [[ -n "$player" ]] && command -v "$player" &>/dev/null; then
        echo "$player"
        return 0
    fi
    
    # Auto-detect
    if command -v mpv &>/dev/null; then
        echo "mpv"
    elif command -v vlc &>/dev/null; then
        echo "vlc"
    else
        echo ""
        return 1
    fi
}

# Set preferred player
set_player_preference() {
    local player="$1"
    config_set "PLAYER" "$player"
}

# Get preferred quality
get_quality_preference() {
    config_get "QUALITY" "1080p"
}

# Set preferred quality
set_quality_preference() {
    local quality="$1"
    config_set "QUALITY" "$quality"
}

# Get TMDB API key
get_tmdb_api_key() {
    config_get "TMDB_API_KEY" ""
}

# Set TMDB API key
set_tmdb_api_key() {
    local key="$1"
    config_set "TMDB_API_KEY" "$key"
}

# Get TMDB read token
get_tmdb_read_token() {
    config_get "TMDB_READ_TOKEN" ""
}

# ═══════════════════════════════════════════════════════════════
# CACHE MANAGEMENT
# ═══════════════════════════════════════════════════════════════

# Clear all cache
clear_cache() {
    local cache_dir=$(get_cache_dir)
    if [[ -d "$cache_dir" ]]; then
        rm -rf "${cache_dir:?}"/*
        show_success "Cache cleared"
    fi
}

# Generate cache key from arguments
generate_cache_key() {
    local input="$*"
    if command -v md5 &>/dev/null; then
        echo "$input" | md5
    elif command -v md5sum &>/dev/null; then
        echo "$input" | md5sum | cut -d' ' -f1
    else
        # Fallback: simple hash
        echo "$input" | cksum | cut -d' ' -f1
    fi
}

# Check if cache file is valid (less than N seconds old)
is_cache_valid() {
    local cache_file="$1"
    local max_age="${2:-3600}"  # Default 1 hour
    
    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi
    
    local now=$(date +%s)
    local file_time
    
    # macOS vs Linux stat
    if stat -f %m "$cache_file" &>/dev/null; then
        file_time=$(stat -f %m "$cache_file")
    else
        file_time=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
    fi
    
    local age=$((now - file_time))
    [[ $age -lt $max_age ]]
}

# ═══════════════════════════════════════════════════════════════
# EXPORT FUNCTIONS
# ═══════════════════════════════════════════════════════════════

export -f get_config_dir get_config_file get_cache_dir
export -f config_get config_set
export -f get_player_preference set_player_preference
export -f get_quality_preference set_quality_preference
export -f get_tmdb_api_key set_tmdb_api_key get_tmdb_read_token
export -f clear_cache generate_cache_key is_cache_valid
