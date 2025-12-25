#!/usr/bin/env bash
#
# Termflix Language Module
# Provides language to flag emoji mapping and lookup functions
#
# @version 1.0.0
# @updated 2025-12-25
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_LANGUAGES_LOADED:-}" ]] && return 0
_TERMFLIX_LANGUAGES_LOADED=1

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

# Language data file location (internal, not affected by cache clear)
LANG_SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANGUAGES_DATA_FILE="${LANG_SCRIPT_DIR}/../../data/languages.json"

# ═══════════════════════════════════════════════════════════════
# LANGUAGE LOOKUP FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Get flag emoji for an ISO 639-1 language code
# Usage: get_language_flag "en"
# Returns: 🇬🇧
get_language_flag() {
    local lang_code="$1"
    
    # Return empty if no code provided
    [[ -z "$lang_code" ]] && echo "" && return 0
    
    # Normalize to lowercase
    lang_code=$(echo "$lang_code" | tr '[:upper:]' '[:lower:]')
    
    # Check if data file exists
    if [[ ! -f "$LANGUAGES_DATA_FILE" ]]; then
        echo "🌐"
        return 0
    fi
    
    # Use Python for JSON parsing (most reliable across platforms)
    local flag
    flag=$(python3 -c "
import json
import sys
try:
    with open('$LANGUAGES_DATA_FILE') as f:
        data = json.load(f)
    lang = '$lang_code'
    if lang in data:
        print(data[lang].get('flag', '🌐'))
    else:
        print('🌐')
except:
    print('🌐')
" 2>/dev/null)
    
    echo "$flag"
}

# Get language name for an ISO 639-1 language code
# Usage: get_language_name "en"
# Returns: English
get_language_name() {
    local lang_code="$1"
    
    [[ -z "$lang_code" ]] && echo "Unknown" && return 0
    
    lang_code=$(echo "$lang_code" | tr '[:upper:]' '[:lower:]')
    
    if [[ ! -f "$LANGUAGES_DATA_FILE" ]]; then
        echo "Unknown"
        return 0
    fi
    
    local name
    name=$(python3 -c "
import json
try:
    with open('$LANGUAGES_DATA_FILE') as f:
        data = json.load(f)
    lang = '$lang_code'
    if lang in data:
        print(data[lang].get('name', 'Unknown'))
    else:
        print('Unknown')
except:
    print('Unknown')
" 2>/dev/null)
    
    echo "$name"
}

# Format language display with flag and name
# Usage: format_language_display "ko"
# Returns: 🇰🇷 Korean
format_language_display() {
    local lang_code="$1"
    
    [[ -z "$lang_code" ]] && echo "" && return 0
    
    local flag name
    flag=$(get_language_flag "$lang_code")
    name=$(get_language_name "$lang_code")
    
    if [[ -n "$flag" && "$name" != "Unknown" ]]; then
        echo "${flag} ${name}"
    elif [[ -n "$flag" ]]; then
        echo "$flag"
    else
        echo ""
    fi
}

# Get all available languages (for filter menus)
# Usage: get_all_languages
# Returns: List of "code|flag|name" lines
get_all_languages() {
    if [[ ! -f "$LANGUAGES_DATA_FILE" ]]; then
        echo "en|🇬🇧|English"
        return 0
    fi
    
    python3 -c "
import json
try:
    with open('$LANGUAGES_DATA_FILE') as f:
        data = json.load(f)
    for code, info in sorted(data.items(), key=lambda x: x[1].get('name', '')):
        print(f\"{code}|{info.get('flag', '🌐')}|{info.get('name', 'Unknown')}\")
except:
    print('en|🇬🇧|English')
" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════
# EXPORTS
# ═══════════════════════════════════════════════════════════════

export -f get_language_flag get_language_name format_language_display get_all_languages
export LANGUAGES_DATA_FILE
