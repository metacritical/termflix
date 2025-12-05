#!/bin/bash
# Terminal and cursor utilities

# Initialize terminal for display
init_terminal_display() {
    local term_lines=$(tput lines)
    local min_required_rows="${1:-18}"
    local initial_row="${2:-5}"
    
    # Clear terminal
    clear
    tput sc
    tput ed
    tput rc
    
    # Ensure initial_row is valid
    if [ "$initial_row" -lt 1 ]; then
        initial_row=5
    fi
    
    # Check if we have enough space
    if [ $((initial_row + min_required_rows)) -gt "$term_lines" ]; then
        initial_row=$((term_lines - min_required_rows - 2))
        if [ "$initial_row" -lt 1 ]; then
            initial_row=1
        fi
        tput cup "$initial_row" 0
    fi
    
    echo "$initial_row"
}

# Calculate safe start row for next grid row
calculate_next_row() {
    local current_start_row="$1"
    local row_height="$2"
    local term_lines=$(tput lines)
    local available_lines=$((term_lines - current_start_row - row_height))
    
    local next_row=$((current_start_row + row_height))
    
    if [ "$next_row" -ge "$term_lines" ] || [ "$available_lines" -lt "$row_height" ]; then
        local lines_to_scroll=$((row_height - available_lines + 5))
        if [ "$lines_to_scroll" -lt 3 ]; then
            lines_to_scroll=3
        fi
        
        for ((scroll=0; scroll<lines_to_scroll; scroll++)); do
            echo
        done
        
        next_row=$((current_start_row + row_height - lines_to_scroll))
        if [ "$next_row" -lt 0 ]; then
            next_row=1
        fi
        
        if [ "$next_row" -ge $((term_lines - row_height - 2)) ]; then
            for ((scroll=0; scroll<row_height; scroll++)); do
                echo
            done
            next_row=$((next_row - row_height))
            if [ "$next_row" -lt 1 ]; then
                next_row=1
            fi
        fi
    fi
    
    echo "$next_row"
}
