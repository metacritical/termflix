#!/usr/bin/env bash

# Quick test to see what fzf_display actually contains

source bin/modules/core/colors.sh
source bin/modules/core/config.sh

# Simulate some results
results=(
    "COMBINED|Predator Badlands 2025|YTS^TPB|1080p^720p|100^200|1.5GB^900MB|mag1^mag2|N/A"
    "YTS|Avatar|magnet123|1080p|2GB|150|http://poster.jpg"
    "TPB|Inception|magnet456|720p|1.5GB|200|http://poster2.jpg"
)

fzf_display=""
i=0

for result in "${results[@]}"; do
    ((i++))
    
    # Parse for display
    IFS='|' read -r source name rest <<< "$result"
    
    # Create display line
    display_line=""
    if [[ "$source" == "COMBINED" ]]; then
        # For COMBINED: extract sources
        IFS='|' read -r sources _ <<< "$rest"
        IFS='^' read -ra sources_arr <<< "$sources"
        badge=""
        for src in "${sources_arr[@]}"; do
            case "$src" in
                "YTS")   badge+="[YTS]" ;;
                "TPB")   badge+="[TPB]" ;;
            esac
        done
        display_line=$(printf "%3d. %-25s %s" "$i" "$badge" "$name")
    else
        badge=""
        case "$source" in
            "YTS")   badge="[YTS]" ;;
            "TPB")   badge="[TPB]" ;;
        esac
        display_line=$(printf "%3d. %-25s %s" "$i" "$badge" "$name")
    fi
    
    fzf_display+="$display_line|$i|$result"$'\n'
done

echo "=== FZF Display Content ==="
echo "$fzf_display"
echo "=== End ===" 

echo ""
echo "=== Testing FZF ===" 
printf "%s" "$fzf_display" | fzf --delimiter='|' --with-nth=1 --exit-0
