#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui_parser.sh"

export menu_header="Test Menu"

# Test the run_fzf_layout logic with non-interactive fzf
echo "=== Testing filtered args ==="

# Simulate what run_fzf_layout does
layout_id="simple-menu"
fzf_args=$(build_fzf_cmd "$layout_id") || exit 1

echo "Original fzf_args:"
echo "$fzf_args"
echo ""

# Convert fzf_args string to array
read -ra xml_arg_array <<< "$fzf_args"

echo "XML arg array (${#xml_arg_array[@]} elements):"
for i in "${!xml_arg_array[@]}"; do
    echo "  [$i]: '${xml_arg_array[$i]}'"
done
echo ""

# Simulate CLI args override
cli_args=("--prompt=Choose > ")
override_flags=("--prompt")

echo "CLI args: ${cli_args[@]}"
echo "Override flags: ${override_flags[@]}"
echo ""

# Filter XML args
-a filtered_args=()
i=0
len=${#xml_arg_array[@]}

while [[ $i -lt $len ]]; do
    arg="${xml_arg_array[$i]}"
    flag_name="${arg%%=*}"
    should_skip=false

    echo "Checking: '$arg' (flag='$flag_name')"

    # Check if this flag is being overridden
    for override in "${override_flags[@]}"; do
        if [[ "$flag_name" == "$override" ]]; then
            should_skip=true
            echo "  -> SKIPPING (overrides $override)"
            # If this flag takes a value (not a flag like --info=hidden), skip next arg too
            if [[ ! "$arg" =~ = ]]; then
                ((i++))
                echo "  -> Also skipping next arg"
            fi
            break
        fi
    done

    if [[ "$should_skip" == false ]]; then
        filtered_args+=("$arg")
        echo "  -> KEEPING"
    fi

    ((i++))
done

echo ""
echo "Filtered args (${#filtered_args[@]} elements):"
for i in "${!filtered_args[@]}"; do
    echo "  [$i]: '${filtered_args[$i]}'"
done

echo ""
echo "Would run: fzf ${filtered_args[*]} ${cli_args[*]}"
