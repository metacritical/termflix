#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui_parser.sh"

# Set environment variables for season-picker
export CLEAN_TITLE="Example Series"
export total_seasons="4"
export THEME_HEX_GLOW="#e879f9"
export THEME_HEX_BG_SELECTION="#374151"

build_fzf_cmd "season-picker"

echo "FZF_PARSED_ARGS has ${#FZF_PARSED_ARGS[@]} elements"
echo ""

# Show exactly what will be passed
echo "Will pass to fzf:"
printf '"%s"\n' "${FZF_PARSED_ARGS[@]}"
echo ""

# Try running with set -x to see exact execution
echo "Running with set -x..."
set -x
echo -e "● Season 1\n○ Season 2\n○ Season 3\n○ Season 4" | timeout 1 fzf "${FZF_PARSED_ARGS[@]}" 2>&1 || true
set +x
