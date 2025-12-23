#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui_parser.sh"

# Test building args for season-picker
export CLEAN_TITLE="Example Series"
export total_seasons="4"
export THEME_HEX_GLOW="#e879f9"
export THEME_HEX_BG_SELECTION="#374151"

build_fzf_cmd "season-picker"

echo "FZF_PARSED_ARGS has ${#FZF_PARSED_ARGS[@]} elements"
echo ""

# Check for empty elements
for i in "${!FZF_PARSED_ARGS[@]}"; do
    if [[ -z "${FZF_PARSED_ARGS[$i]}" ]]; then
        echo "WARNING: Empty element at index $i"
    else
        printf "[%2d]: '%s'\n" "$i" "${FZF_PARSED_ARGS[$i]}"
    fi
done
