#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui_parser.sh"

# Set environment variables for season-picker
export CLEAN_TITLE="Example Series"
export total_seasons="4"
export THEME_HEX_GLOW="#e879f9"
export THEME_HEX_BG_SELECTION="#374151"

# Simulate what run_fzf_layout does for season-picker (no extra args)
echo "=== Testing run_fzf_layout for season-picker ==="
build_fzf_cmd "season-picker"

echo "FZF_PARSED_ARGS has ${#FZF_PARSED_ARGS[@]} elements"
echo ""

# Now run fzf with the parsed args
echo "Running fzf..."
echo -e "● Season 1\n○ Season 2\n○ Season 3\n○ Season 4" | timeout 2 fzf "${FZF_PARSED_ARGS[@]}" 2>&1 || echo "Exit code: $?"
