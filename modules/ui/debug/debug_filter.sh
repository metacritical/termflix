#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui_parser.sh"

# Simulate what run_fzf_layout does
export menu_header="Test Menu"

# Get fzf args
fzf_args=$(build_fzf_cmd "simple-menu") || exit 1
echo "fzf_args: $fzf_args"
echo ""

# Simulate filtering with --prompt override
cli_args=("--prompt" "Choose > ")
override_flags=("--prompt")

echo "Override flags: ${override_flags[@]}"
echo ""

# Filter XML args
filtered_args=()
skip_next=false

while IFS= read -r arg; do
    echo "Processing arg: '$arg' (skip_next=$skip_next)"

    if [[ "$skip_next" == true ]]; then
        echo "  -> Skipping (was flag value)"
        skip_next=false
        continue
    fi

    local should_skip=false
    local flag_name="${arg%%=*}"
    echo "  -> flag_name: '$flag_name'"

    # Check if this flag is being overridden
    for override in "${override_flags[@]}"; do
        if [[ "$flag_name" == "$override" ]]; then
            should_skip=true
            echo "  -> MATCH with override '$override', will skip"
            # If this flag takes a value (not a flag like --info=hidden), skip next arg too
            if [[ ! "$arg" =~ = ]]; then
                echo "  -> Will skip next arg too (flag without =)"
                skip_next=true
            fi
            break
        fi
    done

    if [[ "$should_skip" == false ]]; then
        filtered_args+=("$arg")
        echo "  -> KEEPING in filtered_args"
    fi
done <<< "$fzf_args"

echo ""
echo "Filtered args: ${filtered_args[@]}"
echo ""
echo "Would run: fzf ${filtered_args[*]} ${cli_args[*]}"
