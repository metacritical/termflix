#!/usr/bin/env bash
#
# Termflix Configuration Module
# Config file management and preferences
#
# @version 1.0.0
# @updated 2025-12-14
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_CONFIG_LOADED:-}" ]] && return 0
_TERMFLIX_CONFIG_LOADED=1

# ═══════════════════════════════════════════════════════════════
# IN-MEMORY CONFIG CACHE (Bash 3.2 compatible)
# ═══════════════════════════════════════════════════════════════

# Cache file location (faster than reading config file repeatedly)
_CONFIG_CACHE_FILE="/tmp/termflix_config_cache_$$"
_CONFIG_CACHE_LOADED=0

# Load config file into cache file
_load_config_cache() {
    local config_file
    config_file=$(get_config_file 2>/dev/null || echo "${HOME}/.config/termflix/config")
    
    # Clear existing cache
    rm -f "$_CONFIG_CACHE_FILE" 2>/dev/null
    
    if [[ -f "$config_file" ]]; then
        # Copy config to cache file (removes comments and empty lines)
        grep -v '^[[:space:]]*#' "$config_file" 2>/dev/null | grep -v '^[[:space:]]*$' > "$_CONFIG_CACHE_FILE" 2>/dev/null
    fi
    
    _CONFIG_CACHE_LOADED=1
}

# Invalidate config cache (call after config_set)
invalidate_config_cache() {
    rm -f "$_CONFIG_CACHE_FILE" 2>/dev/null
    _CONFIG_CACHE_LOADED=0
}

# Cleanup cache on exit
trap 'rm -f "$_CONFIG_CACHE_FILE" 2>/dev/null' EXIT

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

# Read a config value (uses file-based cache for performance)
# Usage: config_get "PLAYER" "mpv"
config_get() {
    local key="$1"
    local default="${2:-}"
    local value=""
    
    # Load cache on first access
    if [[ $_CONFIG_CACHE_LOADED -eq 0 ]]; then
        _load_config_cache
    fi
    
    # Try cache file first
    if [[ -f "$_CONFIG_CACHE_FILE" ]]; then
        value=$(grep "^${key}=" "$_CONFIG_CACHE_FILE" 2>/dev/null | head -1 | cut -d'=' -f2-)
        # Strip surrounding quotes and whitespace
        value=$(echo "$value" | tr -d '[:space:]' | sed 's/^["'"'"']//;s/["'"'"']$//')
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
    
    # Invalidate cache so next read picks up the change
    invalidate_config_cache
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
    local key=$(config_get "TMDB_API_KEY" "")
    [[ -z "$key" ]] && key="${TMDB_API_KEY:-}"
    echo "$key"
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
# OMDB API KEY MANAGEMENT
# ═══════════════════════════════════════════════════════════════

# Get OMDB API key
get_omdb_api_key() {
    local key=$(config_get "OMDB_API_KEY" "")
    [[ -z "$key" ]] && key="${OMDB_API_KEY:-}"
    echo "$key"
}

# Set OMDB API key
set_omdb_api_key() {
    local key="$1"
    config_set "OMDB_API_KEY" "$key"
}

# ═══════════════════════════════════════════════════════════════
# FEATURE FLAGS - Python Backend Migration
# ═══════════════════════════════════════════════════════════════

# Check if Python catalog backend should be used
# Falls back to: ENV var → config file → default (false)
# Usage: use_python_catalog && ... || ...
use_python_catalog() {
    # Check environment variable first
    if [[ -n "${USE_PYTHON_CATALOG:-}" ]]; then
        [[ "${USE_PYTHON_CATALOG}" == "true" ]] && return 0 || return 1
    fi
    
    # Check config file
    local value=$(config_get "USE_PYTHON_CATALOG" "false")
    [[ "$value" == "true" ]] && return 0 || return 1
}

# Check if Python API backend should be used
# Falls back to: ENV var → config file → default (false)
# Usage: use_python_api && ... || ...
use_python_api() {
    # Check environment variable first
    if [[ -n "${USE_PYTHON_API:-}" ]]; then
        [[ "${USE_PYTHON_API}" == "true" ]] && return 0 || return 1
    fi
    
    # Check config file
    local value=$(config_get "USE_PYTHON_API" "false")
    [[ "$value" == "true" ]] && return 0 || return 1
}

# Enable Python catalog backend
enable_python_catalog() {
    config_set "USE_PYTHON_CATALOG" "true"
}

# Disable Python catalog backend
disable_python_catalog() {
    config_set "USE_PYTHON_CATALOG" "false"
}

# Enable Python API backend
enable_python_api() {
    config_set "USE_PYTHON_API" "true"
}

# Disable Python API backend
disable_python_api() {
    config_set "USE_PYTHON_API" "false"
}

# ═══════════════════════════════════════════════════════════════
# CONFIG VALIDATION
# ═══════════════════════════════════════════════════════════════

# Validate API key format (basic check - non-empty, reasonable length, valid chars)
# Usage: validate_api_key "key" [min_length] [max_length]
# Returns: 0 if valid, 1 if invalid
validate_api_key() {
    local key="$1"
    local min_length="${2:-8}"
    local max_length="${3:-100}"
    
    # Must be non-empty
    [[ -z "$key" ]] && return 1
    
    # Check length bounds
    [[ ${#key} -lt $min_length ]] && return 1
    [[ ${#key} -gt $max_length ]] && return 1
    
    # Check for valid characters (alphanumeric, dashes, underscores)
    [[ ! "$key" =~ ^[a-zA-Z0-9_-]+$ ]] && return 1
    
    return 0
}

# Validate full config and report issues
# Returns: 0 if all valid, 1 if issues found (prints issues to stdout)
validate_config() {
    local issues=()
    
    # Check TMDB key format (32-40 chars typical)
    local tmdb_key=$(get_tmdb_api_key)
    if [[ -n "$tmdb_key" ]] && ! validate_api_key "$tmdb_key" 32 40; then
        issues+=("TMDB_API_KEY: Invalid format (expected 32-40 alphanumeric chars)")
    fi
    
    # Check OMDB key format (8-16 chars typical)
    local omdb_key=$(get_omdb_api_key)
    if [[ -n "$omdb_key" ]] && ! validate_api_key "$omdb_key" 8 16; then
        issues+=("OMDB_API_KEY: Invalid format (expected 8-16 alphanumeric chars)")
    fi
    
    # Check player preference exists
    local player=$(config_get "PLAYER" "")
    if [[ -n "$player" ]] && ! command -v "$player" &>/dev/null; then
        issues+=("PLAYER: '$player' not found in PATH")
    fi
    
    # Check quality is valid
    local quality=$(config_get "QUALITY" "")
    if [[ -n "$quality" ]] && [[ ! "$quality" =~ ^(720p|1080p|2160p|4k)$ ]]; then
        issues+=("QUALITY: Invalid value '$quality' (expected 720p/1080p/2160p/4k)")
    fi
    
    # Output issues
    if [[ ${#issues[@]} -gt 0 ]]; then
        printf '%s\n' "${issues[@]}"
        return 1
    fi
    
    return 0
}

# ═══════════════════════════════════════════════════════════════
# FALLBACK DEFAULTS (Bash 3.2 compatible - uses case statement)
# ═══════════════════════════════════════════════════════════════

# Get default value for a config key
# Usage: get_config_default "KEY"
get_config_default() {
    local key="$1"
    case "$key" in
        PLAYER)         echo "mpv" ;;
        QUALITY)        echo "1080p" ;;
        CACHE_TTL)      echo "3600" ;;
        POSTER_WIDTH)   echo "20" ;;
        POSTER_HEIGHT)  echo "15" ;;
        API_TIMEOUT)    echo "10" ;;
        TMDB_API_KEY)   echo "" ;;
        OMDB_API_KEY)   echo "" ;;
        TMDB_READ_TOKEN) echo "" ;;
        YTS_CACHE_TTL)  echo "3600" ;;  # 1 hour cache
        YTS_MAX_RETRIES) echo "3" ;;    # 3 retry attempts
        YTS_TIMEOUT)    echo "10" ;;    # 10 second timeout
        USE_PYTHON_CATALOG) echo "true" ;;   # Feature flag: use Python catalog backend (DEFAULT: ENABLED as of Dec 2025)
        USE_PYTHON_API) echo "true" ;;       # Feature flag: use Python API backend (DEFAULT: ENABLED as of Dec 2025)
        *)              echo "" ;;
    esac
}

# Get config value with fallback to registered default
# Usage: config_get_default "KEY"
config_get_default() {
    local key="$1"
    local default
    default=$(get_config_default "$key")
    config_get "$key" "$default"
}

# List all default keys and values
list_config_defaults() {
    echo "API_TIMEOUT=$(get_config_default API_TIMEOUT)"
    echo "CACHE_TTL=$(get_config_default CACHE_TTL)"
    echo "OMDB_API_KEY=$(get_config_default OMDB_API_KEY)"
    echo "PLAYER=$(get_config_default PLAYER)"
    echo "POSTER_HEIGHT=$(get_config_default POSTER_HEIGHT)"
    echo "POSTER_WIDTH=$(get_config_default POSTER_WIDTH)"
    echo "QUALITY=$(get_config_default QUALITY)"
    echo "TMDB_API_KEY=$(get_config_default TMDB_API_KEY)"
    echo "TMDB_READ_TOKEN=$(get_config_default TMDB_READ_TOKEN)"
    echo "YTS_CACHE_TTL=$(get_config_default YTS_CACHE_TTL)"
    echo "YTS_MAX_RETRIES=$(get_config_default YTS_MAX_RETRIES)"
    echo "YTS_TIMEOUT=$(get_config_default YTS_TIMEOUT)"
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
export -f config_get config_set invalidate_config_cache
export -f get_player_preference set_player_preference
export -f get_quality_preference set_quality_preference
export -f get_tmdb_api_key set_tmdb_api_key get_tmdb_read_token
export -f get_omdb_api_key set_omdb_api_key
export -f use_python_catalog use_python_api
export -f enable_python_catalog disable_python_catalog
export -f enable_python_api disable_python_api
export -f validate_api_key validate_config
export -f config_get_default get_config_default list_config_defaults
export -f clear_cache generate_cache_key is_cache_valid
