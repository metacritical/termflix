#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui_parser.sh"

# Test building args for season-picker
echo "=== Building args for season-picker ==="
export CLEAN_TITLE="Test Series"
export total_seasons="4"

build_fzf_cmd "season-picker"

echo ""
echo "FZF_ARGS (${#FZF_ARGS[@]} elements):"
for i in "${!FZF_ARGS[@]}"; do
    printf "[%2d]: '%s'\n" "$i" "${FZF_ARGS[$i]}"
done

echo ""
echo "Testing each arg that would be passed to fzf:"
for i in "${!FZF_ARGS[@]}"; do
    arg="${FZF_ARGS[$i]}"
    if [[ "$arg" =~ ^-- ]]; then
        echo "Flag: '$arg'"
    elif [[ "$i" -gt 0 ]] && [[ "${FZF_ARGS[$((i-1))]}" =~ ^--[^=]+$ ]]; then
        echo "  Value for '${FZF_ARGS[$((i-1))]}': '$arg'"
    fi
done
