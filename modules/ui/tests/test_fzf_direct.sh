#!/usr/bin/env bash
set -euo pipefail

# Test fzf directly with the season-picker args
args=(
    --layout reverse
    --height 70%
    --margin 15%,20%
    --padding 1
    --info=inline
    --header "Series: Test Series (4 seasons)"
    --header-first
    --border rounded
    --border-label " [ Enter:Select | Esc:Back ] "
    --border-label-pos bottom
    --prompt "Select Season ➜"
    --pointer ➜
    --color "fg:#F8F8F2,bg:-1,hl:#E879F9,fg+:#ffffff,bg+:#6855DE,hl+:#E879F9,info:#7D56F4,prompt:#04B575,pointer:#E879F9,marker:#E879F9,spinner:#E879F9,header:#7D56F4"
    --bind esc:abort
)

echo "Args: ${args[@]}"
echo ""
echo "Testing fzf with args (press Ctrl+C):"
echo -e "● Season 1\n○ Season 2\n○ Season 3\n○ Season 4" | timeout 2 fzf "${args[@]}" || echo "Exit code: $?"
