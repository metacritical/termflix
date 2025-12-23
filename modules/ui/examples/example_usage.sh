#!/usr/bin/env bash
#
# Example: Using the XML-based UI Layout Parser
# This demonstrates how to replace hardcoded fzf calls with layout definitions

set -euo pipefail

# Source the parser
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui_parser.sh"

# Example 1: Simple menu selection
example_simple_menu() {
    local menu_items="Option 1\nOption 2\nOption 3\nOption 4"
    local selection

    export menu_header="Example Menu"
    selection=$(printf "%s" "$menu_items" | run_fzf_layout "simple-menu" \
        --prompt="Choose > ")

    echo "Selected: $selection"
}

# Example 2: Episode picker (simulated data)
example_episode_picker() {
    # Simulate episode data
    local episode_list="1|E01 - Pilot                 │ Jan 01, 2025
2|E02 - The Beginning        │ Jan 08, 2025
3|E03 - Rising Action       │ Jan 15, 2025
4|E04 - Climax              │ Jan 22, 2025"

    # Set environment variables that layout expects
    export CLEAN_TITLE="Example Series"
    export SEASON_NUM="1"
    export UI_DIR="${UI_DIR:-/path/to/modules/ui}"

    local results
    results=$(printf "%s" "$episode_list" | run_fzf_layout "episode-picker")

    local key
    local selected
    key=$(echo "$results" | head -1)
    selected=$(echo "$results" | tail -1)

    case "$key" in
        enter)
            local ep_num
            ep_num=$(echo "$selected" | cut -d'|' -f1)
            echo "Playing episode: $ep_num"
            ;;
        ctrl-e|ctrl-s)
            echo "Switching season..."
            ;;
        ctrl-h|ctrl-l|esc)
            echo "Going back..."
            ;;
    esac
}

# Example 3: Season picker (simulated)
example_season_picker() {
    local season_list="● Season 1
○ Season 2
○ Season 3
○ Season 4"

    export CLEAN_TITLE="Example Series"
    export total_seasons="4"
    export THEME_HEX_GLOW="#e879f9"
    export THEME_HEX_BG_SELECTION="#374151"

    local selected
    selected=$(printf "%s" "$season_list" | run_fzf_layout "season-picker")

    if [[ -n "$selected" ]]; then
        local season_num
        season_num=$(echo "$selected" | grep -oE '[0-9]+')
        echo "Selected season: $season_num"
    fi
}

# Example 4: Build fzf args only (without running)
example_build_args() {
    local args
    args=$(build_fzf_cmd "main-catalog")
    echo "Generated fzf arguments for main-catalog:"
    echo "$args" | tr ' ' '\n' | sed 's/^/  /'
}

# Example 5: Custom environment variable expansion
example_custom_layout() {
    local data="Movie A - 2024
Movie B - 2023
Movie C - 2025"

    export menu_header="🎬 Browse Movies (2025)"
    local selection
    selection=$(printf "%s" "$data" | run_fzf_layout "simple-menu" \
        --prompt="Movie > ")

    echo "Selected: $selection"
}

# Run example based on argument
main() {
    case "${1:-all}" in
        simple)
            echo "=== Simple Menu Example ==="
            example_simple_menu
            ;;
        episode)
            echo "=== Episode Picker Example ==="
            example_episode_picker
            ;;
        season)
            echo "=== Season Picker Example ==="
            example_season_picker
            ;;
        build)
            echo "=== Build Arguments Example ==="
            example_build_args
            ;;
        custom)
            echo "=== Custom Layout Example ==="
            example_custom_layout
            ;;
        all)
            echo "Running all examples..."
            echo
            example_build_args
            echo
            example_simple_menu
            echo
            example_season_picker
            ;;
        --help|-h)
            echo "Usage: $0 [simple|episode|season|build|custom|all]"
            echo ""
            echo "Examples:"
            echo "  $0 simple      - Show simple menu picker"
            echo "  $0 episode     - Show episode picker with preview"
            echo "  $0 season      - Show season picker popup"
            echo "  $0 build       - Show generated fzf arguments"
            echo "  $0 custom      - Show custom variable expansion"
            echo "  $0 all         - Run all examples"
            ;;
        *)
            echo "Unknown example: $1"
            echo "Run $0 --help for usage"
            exit 1
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
