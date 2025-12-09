#!/usr/bin/env bash

# Test the display formatting
result="COMBINED|Predator Badlands 2025|YTS^TPB|1080p^720p|100^200|1.5GB^900MB|mag1^mag2|N/A"

IFS='|' read -r source name rest <<< "$result"

echo "Source: [$source]"
echo "Name: [$name]"
echo "Rest: [$rest]"

if [[ "$source" == "COMBINED" ]]; then
    IFS='|' read -r sources _ <<< "$rest"
    echo "Sources field: [$sources]"
    
    IFS='^' read -ra sources_arr <<< "$sources"
    echo "Sources array: ${sources_arr[@]}"
    
    badge=""
    for src in "${sources_arr[@]}"; do
        case "$src" in
            "YTS")   badge+="[YTS]" ;;
            "TPB")   badge+="[TPB]" ;;
            "EZTV")  badge+="[EZTV]" ;;
            "1337x") badge+="[1337x]" ;;
        esac
    done
    
    echo "Badge: [$badge]"
    
    display_line=$(printf "%3d. %-25s %s" 1 "$badge" "$name")
    echo "Display line: [$display_line]"
    
    # Build the full line
    full_line="$display_line|1|$result"
    echo "Full line: [$full_line]"
    
    # Show what FZF would see with --with-nth=1
    IFS='|' read -r first_field rest <<< "$full_line"
    echo "First field (what FZF shows): [$first_field]"
fi
