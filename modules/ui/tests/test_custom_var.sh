#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui_parser.sh"

# Test variable expansion with --filter for non-interactive testing
export menu_header="🎬 Browse Movies (2025)"

selection=$(echo -e "Movie A - 2024\nMovie B - 2023\nMovie C - 2025" | run_fzf_layout "simple-menu" --filter "Movie A")

echo "Menu header should be: 🎬 Browse Movies (2025)"
echo "Selection: $selection"
