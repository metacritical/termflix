#!/usr/bin/env bash
#
# Termflix Posters Module
# VIU ANSI caching, poster fetching, and display functions
#

# ============================================================
# VIU ANSI CACHING SYSTEM
# Pre-renders poster images with viu and caches the ANSI escape
# sequences for instant display (~4x faster than rendering each time)
# ============================================================

# Get the VIU render cache directory
get_viu_cache_dir() {
    local cache_dir="$HOME/.config/termflix/cache/viu_renders"
    mkdir -p "$cache_dir" 2>/dev/null
    echo "$cache_dir"
}

# Generate cache key from image source and dimensions
viu_cache_key() {
    local image_source="$1"
    local width="${2:-15}"
    local height="${3:-10}"
    
    local key_input="${image_source}_${width}x${height}"
    local hash
    hash=$(echo "$key_input" | md5 2>/dev/null || echo "$key_input" | md5sum 2>/dev/null | cut -d' ' -f1)
    echo "${hash:0:16}"
}

# Check if cached viu render exists and is valid
viu_cache_exists() {
    local cache_key="$1"
    local cache_dir
    cache_dir=$(get_viu_cache_dir)
    local cache_file="${cache_dir}/${cache_key}.ansi"
    
    if [ -f "$cache_file" ] && [ -s "$cache_file" ]; then
        return 0  # Cache hit
    fi
    return 1  # Cache miss
}

# Pre-render image with viu and cache the ANSI output
prerender_poster_viu() {
    local image_file="$1"
    local width="${2:-15}"
    local height="${3:-10}"
    local cache_key="${4:-}"
    
    if [ ! -f "$image_file" ] || [ ! -s "$image_file" ]; then
        return 1
    fi
    
    # Generate cache key if not provided
    if [ -z "$cache_key" ]; then
        cache_key=$(viu_cache_key "$image_file" "$width" "$height")
    fi
    
    local cache_dir
    cache_dir=$(get_viu_cache_dir)
    local cache_file="${cache_dir}/${cache_key}.ansi"
    
    # Check if already cached
    if [ -f "$cache_file" ] && [ -s "$cache_file" ]; then
        echo "$cache_file"
        return 0
    fi
    
    # Check if viu is available
    if ! command -v viu &> /dev/null; then
        return 1
    fi
    
    # Pre-render with viu and capture ANSI output
    viu -w "$width" -h "$height" "$image_file" 2>/dev/null > "$cache_file"
    
    if [ -f "$cache_file" ] && [ -s "$cache_file" ]; then
        echo "$cache_file"
        return 0
    fi
    
    rm -f "$cache_file" 2>/dev/null
    return 1
}

# Display cached viu render (instant - just cat the ANSI file)
display_cached_viu() {
    local cache_file="$1"
    local x_pos="${2:-}"
    local y_pos="${3:-}"
    
    if [ ! -f "$cache_file" ] || [ ! -s "$cache_file" ]; then
        return 1
    fi
    
    # Position cursor if coordinates provided
    if [ -n "$x_pos" ] && [ -n "$y_pos" ]; then
        tput cup "$y_pos" "$x_pos" 2>/dev/null || true
    fi
    
    # Instant display - just cat the pre-rendered ANSI
    cat "$cache_file"
    return 0
}

# Background pre-render multiple posters in parallel
prerender_posters_batch() {
    local width="${1:-15}"
    local height="${2:-10}"
    shift 2
    local image_files=("$@")
    
    local pids=()
    for image_file in "${image_files[@]}"; do
        if [ -f "$image_file" ] && [ -s "$image_file" ]; then
            prerender_poster_viu "$image_file" "$width" "$height" &
            pids+=($!)
        fi
    done
    
    # Wait for all background renders to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
}

# Clean up old viu cache files (older than 7 days)
cleanup_viu_cache() {
    local cache_dir
    cache_dir=$(get_viu_cache_dir)
    
    if [ -d "$cache_dir" ]; then
        find "$cache_dir" -name "*.ansi" -type f -mtime +7 -delete 2>/dev/null || true
    fi
}

# ============================================================
# POSTER DISPLAY
# ============================================================

# Download and display poster image (with VIU caching)
display_poster() {
    local poster_source="$1"  # Can be a URL or a cached file path
    local width="${2:-20}"
    local height="${3:-15}"
    local x_pos="${4:-}"
    local y_pos="${5:-}"
    
    if [ -z "$poster_source" ] || [ "$poster_source" = "N/A" ] || [ "$poster_source" = "" ]; then
        return 1
    fi
    
    local image_file=""
    
    # Check if it's already a cached file path
    if [ -f "$poster_source" ]; then
        image_file="$poster_source"
    else
        # It's a URL, download it to temp directory
        local temp_dir="${TMPDIR:-/tmp}/torrent_posters_$$"
        mkdir -p "$temp_dir" 2>/dev/null || return 1
        
        local hash=$(echo "$poster_source" | md5 2>/dev/null || echo "$poster_source" | md5sum 2>/dev/null | cut -d' ' -f1)
        image_file="${temp_dir}/poster_$(echo "$hash" | cut -c1-8).jpg"
        
        if [ ! -f "$image_file" ]; then
            curl -s --max-time 5 "$poster_source" -o "$image_file" 2>/dev/null || return 1
        fi
    fi
    
    if [ ! -f "$image_file" ] || [ ! -s "$image_file" ]; then
        return 1
    fi

    # Check for Kitty terminal (native image protocol)
    if [[ "$TERM" == "xterm-kitty" ]] && command -v kitty &> /dev/null; then
        if [ -n "$x_pos" ] && [ -n "$y_pos" ]; then
            tput cup "$y_pos" "$x_pos"
            kitty +kitten icat --align left --place "${width}x${height}@${x_pos}x${y_pos}" "$image_file" 2>/dev/null
        else
            kitty +kitten icat --align left --height "$height" "$image_file" 2>/dev/null
        fi
        return 0
    fi
    
    # VIU with ANSI caching
    if check_viu > /dev/null 2>&1; then
        local cache_key
        cache_key=$(viu_cache_key "$image_file" "$width" "$height")
        local cache_dir
        cache_dir=$(get_viu_cache_dir)
        local cached_ansi="${cache_dir}/${cache_key}.ansi"
        
        # Try cached render first
        if [ -f "$cached_ansi" ] && [ -s "$cached_ansi" ]; then
            display_cached_viu "$cached_ansi" "$x_pos" "$y_pos"
            return 0
        fi
        
        # Cache miss - pre-render and cache
        local new_cache
        new_cache=$(prerender_poster_viu "$image_file" "$width" "$height" "$cache_key")
        
        if [ -n "$new_cache" ] && [ -f "$new_cache" ]; then
            display_cached_viu "$new_cache" "$x_pos" "$y_pos"
            return 0
        fi
        
        # Fallback: direct viu render
        if [ -n "$x_pos" ] && [ -n "$y_pos" ]; then
            tput cup "$y_pos" "$x_pos"
            viu -w "$width" -h "$height" "$image_file" 2>/dev/null
        else
            viu -w "$width" -h "$height" "$image_file" 2>/dev/null
        fi
        return 0
    fi
    
    return 1
}

# ============================================================
# POSTER FETCHING (Google Images)
# ============================================================

# Fetch poster URL from Google Images (wrapper to Python script)
fetch_google_poster() {
    local query="$1"
    
    if ! command -v python3 &> /dev/null; then
        return 1
    fi
    
    export POSTER_QUERY="$query"
    python3 "$TERMFLIX_SCRIPTS_DIR/google_poster.py" 2>/tmp/termflix_last_error.log
}

# ============================================================
# TMDB POSTER ENRICHMENT
# ============================================================

# Enrich catalog entries with missing posters from TMDB/YTS/OMDb/Google (priority chain)
enrich_missing_posters() {
    local cached_results_var="$1"
    local max_enrich="${2:-20}"  # Limit enrichments per call
    
    eval "local -a items=(\"\${${cached_results_var}[@]}\")"
    
    local need_enrichment=false
    for item in "${items[@]}"; do
        IFS='|' read -r source name magnet quality size extra poster_url <<< "$item"
        if [[ "$poster_url" == "N/A" ]] || [[ -z "$poster_url" ]]; then
            need_enrichment=true
            break
        fi
    done
    
    if [ "$need_enrichment" = false ]; then
        return 0
    fi
    
    # Use get_poster.py which has priority: TMDB → YTS → OMDb → Google
    # Using newer implementation from lib/termflix/scripts/
    local poster_script="${SCRIPT_DIR}/../lib/termflix/scripts/get_poster.py"
    
    # Parallel enrichment with limit
    {
        local enriched=0
        for i in "${!items[@]}"; do
            [ "$enriched" -ge "$max_enrich" ] && break
            
            local item="${items[$i]}"
            IFS='|' read -r source name magnet quality size extra poster_url <<< "$item"
            
            if [[ "$poster_url" == "N/A" ]] || [[ -z "$poster_url" ]]; then
                local new_poster
                if [[ -f "$poster_script" ]]; then
                    new_poster=$(timeout 5s python3 "$poster_script" "$name" 2>/dev/null)
                else
                    new_poster=$(fetch_google_poster "$name" 2>/dev/null)
                fi
                
                if [[ -n "$new_poster" ]] && [[ "$new_poster" != "N/A" ]] && [[ "$new_poster" != "null" ]]; then
                    items[$i]="${source}|${name}|${magnet}|${quality}|${size}|${extra}|${new_poster}"
                    enriched=$((enriched + 1))
                fi
            fi
        done
        
        # Update the cached results
        eval "${cached_results_var}=(\"\${items[@]}\")"
    } &
    local enrich_pid=$!
    
    show_spinner "$enrich_pid" "Fetching missing posters..."
}
