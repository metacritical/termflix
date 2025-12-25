#!/usr/bin/env bash
#
# Termflix Async Catalog Loader for FZF reload binding
# This script is called by FZF's reload() to get fresh catalog data
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source required modules
source "$ROOT_DIR/modules/catalog/fetching.sh" 2>/dev/null || true

# Configuration
CATEGORY="${1:-movies}"
PAGE="${2:-1}"
ITEMS_PER_PAGE="${3:-53}"
FORCE_REFRESH="${4:-false}"

# Cache file location
CACHE_DIR="${HOME}/.cache/termflix"
CATALOG_CACHE="${CACHE_DIR}/catalog_enriched_${CATEGORY}.txt"

# If force refresh, fetch new data
if [[ "$FORCE_REFRESH" == "true" ]] || [[ ! -f "$CATALOG_CACHE" ]]; then
    # Call Python script to fetch fresh data
    PYTHON_SCRIPT="$ROOT_DIR/scripts/python/fetch_multi_source_catalog.py"
    if [[ -f "$PYTHON_SCRIPT" ]]; then
        python3 "$PYTHON_SCRIPT" --yts-pages 10 --category "$CATEGORY" ${FORCE_REFRESH:+--refresh} > "$CATALOG_CACHE" 2>/dev/null
    fi
fi

# Read and format for FZF display
if [[ -f "$CATALOG_CACHE" ]]; then
    i=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" != *"|"* ]] && continue
        ((i++))
        
        # Parse for display
        IFS='|' read -r source name rest <<< "$line"
        name="${name%|}"
        
        # Format: "display<TAB>index|data" for FZF
        printf "%3d. %s\t%d|%s\n" "$i" "$name" "$i" "$line"
    done < "$CATALOG_CACHE"
fi
