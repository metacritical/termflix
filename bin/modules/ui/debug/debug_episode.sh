#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui_parser.sh"

# Test building args for episode-picker
echo "=== Building args for episode-picker ==="
export CLEAN_TITLE="Test Series"
export SEASON_NUM="1"
export SCRIPT_DIR="/path/to/scripts"

build_fzf_cmd "episode-picker"

echo ""
echo "FZF_ARGS (${#FZF_ARGS[@]} elements):"
for i in "${!FZF_ARGS[@]}"; do
    echo "  [$i]: '${FZF_ARGS[$i]}'"
done

echo ""
echo "FZF_PARSED_ARGS (${#FZF_PARSED_ARGS[@]} elements):"
for i in "${!FZF_PARSED_ARGS[@]}"; do
    echo "  [$i]: '${FZF_PARSED_ARGS[$i]}'"
done

echo ""
echo "Would run: fzf ${FZF_PARSED_ARGS[*]}"
