#!/usr/bin/env bash
#
# FZF Layout Parser
# Parses XML layout definitions and generates fzf command-line arguments
# Usage: source ui_parser.sh; build_fzf_cmd "layout_id"

# Script directory - safer sourcing
_UI_PARSER_SCRIPT="${BASH_SOURCE[0]:-${(%):-%x}}"
UI_PARSER_DIR="$(cd "$(dirname "$_UI_PARSER_SCRIPT")" && pwd)"
UI_DIR="$(cd "${UI_PARSER_DIR}/.." && pwd)"
LAYOUTS_DIR="${UI_DIR}/layouts"
THEME_SCRIPT="${UI_DIR}/../core/theme.sh"
export UI_DIR

# Set strict mode after variable initialization
set -euo pipefail

# Source theme helper if available
[[ -f "$THEME_SCRIPT" ]] && source "$THEME_SCRIPT" 2>/dev/null || true

# FZF command accumulator
declare -a FZF_ARGS=()

# Global array for parsed fzf arguments (set by build_fzf_cmd)
declare -a FZF_PARSED_ARGS=()

# Clear accumulator
_fzf_reset() {
    FZF_ARGS=()
}

# Add argument if not empty
_fzf_add() {
    [[ -n "${1:-}" ]] && FZF_ARGS+=("$1")
}

# Add flag with value
_fzf_add_flag() {
    local flag="$1"
    local value="${2:-}"
    [[ -n "$value" ]] && FZF_ARGS+=("$flag" "$value")
}

# Parse layout element using xmllint
_parse_layout() {
    local xml_file="$1"

    # Extract attributes using xmllint
    local direction height margin padding info
    direction=$(xmllint --xpath 'string(//fzf-layout/@layout-direction)' "$xml_file" 2>/dev/null)
    height=$(xmllint --xpath 'string(//fzf-layout/@layout-height)' "$xml_file" 2>/dev/null)
    margin=$(xmllint --xpath 'string(//fzf-layout/@layout-margin)' "$xml_file" 2>/dev/null)
    padding=$(xmllint --xpath 'string(//fzf-layout/@layout-padding)' "$xml_file" 2>/dev/null)
    info=$(xmllint --xpath 'string(//fzf-layout/@layout-info)' "$xml_file" 2>/dev/null)

    # If using element-based format
    if [[ -z "$direction" ]]; then
        direction=$(xmllint --xpath 'string(//fzf-layout/layout/@direction)' "$xml_file" 2>/dev/null || echo "reverse")
        height=$(xmllint --xpath 'string(//fzf-layout/layout/@height)' "$xml_file" 2>/dev/null || echo "100%")
        margin=$(xmllint --xpath 'string(//fzf-layout/layout/@margin)' "$xml_file" 2>/dev/null || echo "1")
        padding=$(xmllint --xpath 'string(//fzf-layout/layout/@padding)' "$xml_file" 2>/dev/null || echo "1")
        info=$(xmllint --xpath 'string(//fzf-layout/layout/@info)' "$xml_file" 2>/dev/null || echo "default")
    fi

    # Add layout arguments
    _fzf_add_flag "--layout" "$direction"
    [[ -n "$height" && "$height" != "100%" ]] && _fzf_add_flag "--height" "$height"
    [[ -n "$margin" ]] && _fzf_add_flag "--margin" "$margin"
    [[ -n "$padding" ]] && _fzf_add_flag "--padding" "$padding"

    case "$info" in
        hidden) _fzf_add "--info=hidden" ;;
        inline) _fzf_add "--info=inline" ;;
        default) ;;
    esac
    return 0
}

# Parse preview element
_parse_preview() {
    local xml_file="$1"

    # Check if preview element exists
    local has_preview
    has_preview=$(xmllint --xpath 'boolean(//fzf-layout/preview)' "$xml_file" 2>/dev/null || echo "false")
    [[ "$has_preview" != "true" ]] && return

    local position size wrap border script delimiter with_nth
    position=$(xmllint --xpath 'string(//fzf-layout/preview/@position)' "$xml_file" 2>/dev/null || echo "right")
    size=$(xmllint --xpath 'string(//fzf-layout/preview/@size)' "$xml_file" 2>/dev/null || echo "50%")
    wrap=$(xmllint --xpath 'string(//fzf-layout/preview/@wrap)' "$xml_file" 2>/dev/null || echo "true")
    border=$(xmllint --xpath 'string(//fzf-layout/preview/@border)' "$xml_file" 2>/dev/null)
    script=$(xmllint --xpath 'string(//fzf-layout/preview/@script)' "$xml_file" 2>/dev/null)
    delimiter=$(xmllint --xpath 'string(//fzf-layout/preview/@delimiter)' "$xml_file" 2>/dev/null)
    with_nth=$(xmllint --xpath 'string(//fzf-layout/preview/@with-nth)' "$xml_file" 2>/dev/null)

    # Build preview window spec
    local preview_spec="${position}:${size}"
    [[ "$wrap" == "true" ]] && preview_spec+=":wrap"
    [[ -n "$border" ]] && preview_spec+=":${border}"

    _fzf_add_flag "--preview-window" "$preview_spec"
    [[ -n "$script" ]] && _fzf_add_flag "--preview" "$script"
    [[ -n "$delimiter" ]] && _fzf_add_flag "--delimiter" "$delimiter"
    [[ -n "$with_nth" ]] && _fzf_add_flag "--with-nth" "$with_nth"
    return 0
}

# Parse header element
_parse_header() {
    local xml_file="$1"

    local header_content header_first
    header_content=$(xmllint --xpath 'string(//fzf-layout/header)' "$xml_file" 2>/dev/null || echo "")
    header_first=$(xmllint --xpath 'string(//fzf-layout/header/@first)' "$xml_file" 2>/dev/null || echo "true")

    [[ -n "$header_content" ]] && _fzf_add_flag "--header" "$header_content"
    [[ "$header_first" == "true" ]] && _fzf_add "--header-first"
    return 0
}

# Parse border element
_parse_border() {
    local xml_file="$1"

    local border_style border_label label_pos
    border_style=$(xmllint --xpath 'string(//fzf-layout/border/@style)' "$xml_file" 2>/dev/null || echo "rounded")
    border_label=$(xmllint --xpath 'string(//fzf-layout/border/@label)' "$xml_file" 2>/dev/null || echo "")
    label_pos=$(xmllint --xpath 'string(//fzf-layout/border/@label-pos)' "$xml_file" 2>/dev/null || echo "bottom")

    _fzf_add_flag "--border" "$border_style"
    [[ -n "$border_label" ]] && _fzf_add_flag "--border-label" "$border_label"
    [[ -n "$label_pos" ]] && _fzf_add_flag "--border-label-pos" "$label_pos"
    return 0
}

# Parse prompt element
_parse_prompt() {
    local xml_file="$1"

    local prompt_text pointer
    prompt_text=$(xmllint --xpath 'string(//fzf-layout/prompt)' "$xml_file" 2>/dev/null || echo "> ")
    pointer=$(xmllint --xpath 'string(//fzf-layout/prompt/@pointer)' "$xml_file" 2>/dev/null || echo "")

    _fzf_add_flag "--prompt" "$prompt_text"
    [[ -n "$pointer" ]] && _fzf_add_flag "--pointer" "$pointer" || true
    return 0
}

# Parse colors
_parse_colors() {
    local xml_file="$1"

    local theme
    theme=$(xmllint --xpath 'string(//fzf-layout/colors/@theme)' "$xml_file" 2>/dev/null || echo "default")

    # If using get_fzf_colors, try that first
    if declare -F get_fzf_colors &>/dev/null; then
        local theme_colors
        theme_colors=$(get_fzf_colors 2>/dev/null || echo "")
        if [[ -n "$theme_colors" ]]; then
            _fzf_add_flag "--color" "$theme_colors"
            return
        fi
    fi

    # Otherwise parse individual colors
    local color_names=(
        "fg" "bg" "hl" "fg+" "bg+" "hl+"
        "info" "prompt" "pointer" "marker" "spinner" "header" "border" "gutter"
    )

    local color_parts=()
    for color_name in "${color_names[@]}"; do
        local color_value
        color_value=$(xmllint --xpath "string(//fzf-layout/colors/color[@name='$color_name']/@value)" "$xml_file" 2>/dev/null || echo "")

        # Expand variables in color values
        if [[ "$color_value" =~ \$\{.*\} ]]; then
            color_value=$(eval "echo \"$color_value\"")
        fi

        [[ -n "$color_value" ]] && color_parts+=("${color_name}:${color_value}")
    done

    if [[ ${#color_parts[@]} -gt 0 ]]; then
        local color_string
        color_string=$(IFS=,; echo "${color_parts[*]}")
        _fzf_add_flag "--color" "$color_string"
    fi
    return 0
}

# Parse bindings
_parse_bindings() {
    local xml_file="$1"

    # Check if bindings element exists
    local has_bindings
    has_bindings=$(xmllint --xpath 'boolean(//fzf-layout/bindings)' "$xml_file" 2>/dev/null || echo "false")
    [[ "$has_bindings" != "true" ]] && return

    local delimiter with_nth expect
    delimiter=$(xmllint --xpath 'string(//fzf-layout/bindings/@delimiter)' "$xml_file" 2>/dev/null)
    with_nth=$(xmllint --xpath 'string(//fzf-layout/bindings/@with-nth)' "$xml_file" 2>/dev/null)
    expect=$(xmllint --xpath 'string(//fzf-layout/bindings/@expect)' "$xml_file" 2>/dev/null)

    [[ -n "$delimiter" ]] && _fzf_add_flag "--delimiter" "$delimiter"
    [[ -n "$with_nth" ]] && _fzf_add_flag "--with-nth" "$with_nth"
    [[ -n "$expect" ]] && _fzf_add_flag "--expect" "$expect"

    # Parse individual bindings
    local bind_count
    bind_count=$(xmllint --xpath 'count(//fzf-layout/bindings/bind)' "$xml_file" 2>/dev/null || echo "0")

    for ((i=1; i<=bind_count; i++)); do
        local key action return_code script reload
        key=$(xmllint --xpath "string(//fzf-layout/bindings/bind[$i]/@key)" "$xml_file" 2>/dev/null || echo "")
        action=$(xmllint --xpath "string(//fzf-layout/bindings/bind[$i]/@action)" "$xml_file" 2>/dev/null || echo "")
        return_code=$(xmllint --xpath "string(//fzf-layout/bindings/bind[$i]/@return-code)" "$xml_file" 2>/dev/null || echo "")
        script=$(xmllint --xpath "string(//fzf-layout/bindings/bind[$i]/@script)" "$xml_file" 2>/dev/null || echo "")
        reload=$(xmllint --xpath "string(//fzf-layout/bindings/bind[$i]/@reload)" "$xml_file" 2>/dev/null || echo "false")

        [[ -z "$key" ]] && continue

        # Build bind string based on action type
        case "$action" in
            execute)
                if [[ -n "$script" ]]; then
                    local bind_str="--bind=${key}:execute(${script})"
                    [[ "$reload" == "true" ]] && bind_str+="+reload(printf '%s' \"\$fzf_display\")"
                    _fzf_add "$bind_str"
                fi
                ;;
            abort)
                _fzf_add "--bind=${key}:abort"
                ;;
            accept)
                _fzf_add "--bind=${key}:accept"
                ;;
            toggle-preview)
                _fzf_add "--bind=${key}:toggle-preview"
                ;;
            preview-down)
                _fzf_add "--bind=${key}:preview-down"
                ;;
            preview-up)
                _fzf_add "--bind=${key}:preview-up"
                ;;
            "")
                # No action, just return code
                ;;
        esac
    done
    return 0
}

# Main function to build fzf command from XML
build_fzf_cmd() {
    local layout_id="$1"
    local xml_file="${LAYOUTS_DIR}/${layout_id}.xml"

    # Reset accumulator and global array
    _fzf_reset
    FZF_PARSED_ARGS=()

    # Check if file exists
    if [[ ! -f "$xml_file" ]]; then
        echo "Error: Layout file not found: $xml_file" >&2
        return 1
    fi

    # Parse all elements
    _parse_layout "$xml_file"
    _parse_preview "$xml_file"
    _parse_header "$xml_file"
    _parse_border "$xml_file"
    _parse_prompt "$xml_file"
    _parse_colors "$xml_file"
    _parse_bindings "$xml_file"

    # Copy arguments to global array (for direct use)
    FZF_PARSED_ARGS=("${FZF_ARGS[@]}")

    # Export and output for backward compatibility (space-separated)
    export FZF_UI_ARGS="${FZF_ARGS[*]}"
    echo "${FZF_ARGS[*]}"
}

# Run fzf with parsed layout
run_fzf_layout() {
    local layout_id="$1"
    shift  # Remove layout_id from args

    # Build arguments (sets FZF_PARSED_ARGS, suppress output)
    build_fzf_cmd "$layout_id" > /dev/null || return 1

    # If extra args provided, filter out conflicting flags from XML args
    if [[ $# -gt 0 ]]; then
        # Parse CLI args to find flags that should override XML
        local -a cli_args=("$@")
        local -a override_flags=()

        for arg in "${cli_args[@]}"; do
            # Extract flag name (everything before first '=' or the full flag)
            local flag="${arg%%=*}"
            # Handle --flag=value or --flag value format
            if [[ "$flag" =~ ^--.+$ ]]; then
                override_flags+=("$flag")
            fi
        done

        # Filter XML args: remove any flag that's being overridden
        local -a filtered_args=()
        local i=0
        local len=${#FZF_PARSED_ARGS[@]}

        while [[ $i -lt $len ]]; do
            local arg="${FZF_PARSED_ARGS[$i]}"
            local flag_name="${arg%%=*}"
            local should_skip=false

            # Check if this flag is being overridden
            for override in "${override_flags[@]}"; do
                if [[ "$flag_name" == "$override" ]]; then
                    should_skip=true
                    # If this flag takes a value (not a flag like --info=hidden), skip next arg too
                    if [[ ! "$arg" =~ = ]]; then
                        ((i++))
                    fi
                    break
                fi
            done

            if [[ "$should_skip" == false ]]; then
                filtered_args+=("$arg")
            fi

            ((i++))
        done

        # Run fzf with filtered XML args plus CLI args
        fzf "${filtered_args[@]}" "${cli_args[@]}"
    else
        # Use parsed args directly
        fzf "${FZF_PARSED_ARGS[@]}"
    fi
}

# Export functions for sourcing
export -f _fzf_reset _fzf_add _fzf_add_flag
export -f _parse_layout _parse_preview _parse_header _parse_border
export -f _parse_prompt _parse_colors _parse_bindings
export -f build_fzf_cmd run_fzf_layout

# If script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]:-$0}" == "${0:-}" ]]; then
    case "${1:-}" in
        --help|-h)
            echo "Usage: source ui_parser.sh; build_fzf_cmd <layout_id>"
            echo "   or: source ui_parser.sh; run_fzf_layout <layout_id> [extra_args...]"
            echo ""
            echo "Available layouts:"
            ls -1 "${LAYOUTS_DIR}"/*.xml 2>/dev/null | xargs -I{} basename {} .xml | sed 's/^/  /'
            ;;
        --list)
            ls -1 "${LAYOUTS_DIR}"/*.xml 2>/dev/null | xargs -I{} basename {} .xml
            ;;
        --validate)
            layout="${2:-}"
            [[ -z "$layout" ]] && echo "Error: --validate requires a layout_id" >&2 && exit 1
            build_fzf_cmd "$layout" > /dev/null && echo "✓ Valid: $layout" || echo "✗ Invalid: $layout"
            ;;
        *)
            if [[ -n "${1:-}" ]]; then
                build_fzf_cmd "$1"
            fi
            ;;
    esac
fi
