#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui_parser.sh"

# Set environment variables
export menu_header="Test Menu"

# Test simple-menu with non-interactive filter
echo "=== Testing simple-menu (non-interactive) ==="
selection=$(echo -e "Option 1\nOption 2\nOption 3" | run_fzf_layout "simple-menu" --filter "Option 1")
echo "Selected: $selection"

echo ""
echo "=== Testing season-picker (non-interactive) ==="
export CLEAN_TITLE="Example Series"
export total_seasons="4"
export THEME_HEX_GLOW="#e879f9"
export THEME_HEX_BG_SELECTION="#374151"
selection=$(echo -e "● Season 1\n○ Season 2\n○ Season 3\n○ Season 4" | run_fzf_layout "season-picker" --filter "Season 1")
echo "Selected: $selection"

echo ""
echo "=== Testing episode-picker (non-interactive) ==="
export CLEAN_TITLE="Test Series"
export SEASON_NUM="1"
selection=$(echo -e "1|E01 - Pilot|Jan 01\n2|E02 - Episode|Jan 08" | run_fzf_layout "episode-picker" --filter "E01")
echo "Selected: $selection"
