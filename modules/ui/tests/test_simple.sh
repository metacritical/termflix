#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui_parser.sh"

# Test building args for simple-menu
echo "=== Building args for simple-menu ==="
export menu_header="Test Menu"
fzf_args=$(build_fzf_cmd "simple-menu")
echo "Args: $fzf_args"

echo ""
echo "=== Testing with echo and simple input ==="
echo -e "Option 1\nOption 2\nOption 3" | fzf --layout reverse --info=hidden --header "Test Menu" --header-first --border rounded --prompt ">" --color fg:#6b7280,bg:#1e1e2e,hl:#818cf8,fg+:#ffffff,bg+:#5865f2,hl+:#c4b5fd,info:#6b7280,prompt:#5eead4,pointer:#818cf8,marker:#818cf8,spinner:#818cf8,header:#a78bfa,border:#5865f2,gutter:#1e1e2e < /dev/tty || echo "Selection cancelled"
