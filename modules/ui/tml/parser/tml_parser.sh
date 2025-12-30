#!/usr/bin/env bash
#
# Unified TML Parser v2.0
# Combines V1 FZF args generation with V2 rich component rendering
#
# Usage:
#   source tml_parser.sh
#   tml_parse "layout.tml"
#   fzf $(tml_get_fzf_args) --header "$(tml_render_header)"
#
# Or:
#   ./tml_parser.sh fzf-args layout.tml
#   ./tml_parser.sh render-header layout.tml

# NOTE: Do NOT use 'set -euo pipefail' here!
# This script is sourced by parent shells, and strict mode would propagate,
# causing the entire application to exit on any unset variable or error.

# ═══════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════

_TML_PARSER_SCRIPT="${BASH_SOURCE[0]:-${(%):-%x}}"
TML_PARSER_DIR="$(cd "$(dirname "$_TML_PARSER_SCRIPT")" && pwd)"
TML_UI_DIR="$(cd "${TML_PARSER_DIR}/../.." && pwd)"
TML_LAYOUTS_DIR="${TML_UI_DIR}/layouts"
TML_SCHEMA="${TML_PARSER_DIR}/../schema/tml-1.0.xsd"

# Source theme if available
THEME_SCRIPT="${TML_UI_DIR}/../core/theme.sh"
[[ -f "$THEME_SCRIPT" ]] && source "$THEME_SCRIPT" 2>/dev/null || true

# Export for preview scripts
export TML_UI_DIR

# ═══════════════════════════════════════════════════════════════
# STATE (bash 3.2 compatible - no associative arrays)
# ═══════════════════════════════════════════════════════════════

TML_CURRENT_FILE=""
TML_FZF_ARGS=""
TML_EXPECT_KEYS=""
TML_BINDINGS=""

# ═══════════════════════════════════════════════════════════════
# XML PARSING HELPERS
# ═══════════════════════════════════════════════════════════════

tml_attr() {
    local xml_file="$1"
    local xpath="$2"
    xmllint --xpath "string($xpath)" "$xml_file" 2>/dev/null || echo ""
}

tml_text() {
    local xml_file="$1"
    local xpath="$2"
    xmllint --xpath "$xpath/text()" "$xml_file" 2>/dev/null || echo ""
}

tml_count() {
    local xml_file="$1"
    local xpath="$2"
    xmllint --xpath "count($xpath)" "$xml_file" 2>/dev/null || echo "0"
}

tml_exists() {
    local xml_file="$1"
    local xpath="$2"
    local result
    result=$(xmllint --xpath "boolean($xpath)" "$xml_file" 2>/dev/null || echo "false")
    [[ "$result" == "true" ]]
}

# ═══════════════════════════════════════════════════════════════
# EXPRESSION EVALUATOR
# ═══════════════════════════════════════════════════════════════

tml_eval() {
    local input="$1"
    local result="$input"

    # ${var_name}
    while [[ "$result" =~ \$\{([a-zA-Z_][a-zA-Z0-9_]*)\} ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local tml_var="TML_VAR_${var_name}"
        local var_value="${!tml_var:-${!var_name:-}}"
        result="${result//\$\{$var_name\}/$var_value}"
    done

    # ${VAR-default} (default only when VAR is unset; empty string is respected)
    while [[ "$result" =~ \$\{([a-zA-Z_][a-zA-Z0-9_]*)-([^:}][^}]*)\} ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local default_val="${BASH_REMATCH[2]}"
        local tml_var="TML_VAR_${var_name}"
        local var_value=""

        if [[ -n "${!tml_var+x}" ]]; then
            var_value="${!tml_var}"
        elif [[ -n "${!var_name+x}" ]]; then
            var_value="${!var_name}"
        else
            var_value="$default_val"
        fi

        result="${result//\$\{$var_name-$default_val\}/$var_value}"
    done

    # ${VAR:-default}
    while [[ "$result" =~ \$\{([a-zA-Z_][a-zA-Z0-9_]*):-([^}]*)\} ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local default_val="${BASH_REMATCH[2]}"
        local tml_var="TML_VAR_${var_name}"
        local var_value="${!tml_var:-${!var_name:-$default_val}}"
        result="${result//\$\{$var_name:-$default_val\}/$var_value}"
    done

    echo "$result"
}

# Escape special characters for safe shell embedding in double-quoted strings
# Escapes: \ ` $ " !
tml_shell_escape() {
    local input="$1"
    # Escape backslash first, then other special chars
    input="${input//\\/\\\\}"
    input="${input//\`/\\\`}"
    input="${input//\$/\\\$}"
    input="${input//\"/\\\"}"
    input="${input//\!/\\\!}"
    # Also escape single quotes by replacing ' with '\''  
    input="${input//\'/\'}"
    echo "$input"
}

tml_eval_bool() {
    local expr="$1"
    expr="${expr#\$\{}"
    expr="${expr%\}}"

    if [[ "$expr" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*==[[:space:]]*[\'\"]?([^\'\"]*)[\'\"]?$ ]]; then
        local var_name="${BASH_REMATCH[1]}"
        local compare_val="${BASH_REMATCH[2]}"
        local tml_var="TML_VAR_${var_name}"
        local var_value="${!tml_var:-${!var_name:-}}"
        [[ "$var_value" == "$compare_val" ]] && return 0 || return 1
    fi

    local val
    val=$(tml_eval "\${$expr}")
    [[ -n "$val" && "$val" != "false" && "$val" != "0" ]]
}

# ═══════════════════════════════════════════════════════════════
# VARIABLES PARSER
# ═══════════════════════════════════════════════════════════════

_parse_variables() {
    local xml_file="$1"
    local var_count
    var_count=$(tml_count "$xml_file" "//variables/var")

    for ((i=1; i<=var_count; i++)); do
        local name default_val
        name=$(tml_attr "$xml_file" "//variables/var[$i]/@name")
        default_val=$(tml_attr "$xml_file" "//variables/var[$i]/@default")

        local tml_var="TML_VAR_${name}"
        if [[ -z "${!tml_var:-}" ]]; then
            eval "export ${tml_var}=\"${default_val}\""
        fi
    done
}

# ═══════════════════════════════════════════════════════════════
# FZF ARGS GENERATION (from V1)
# ═══════════════════════════════════════════════════════════════

_parse_fzf_layout() {
    local xml_file="$1"
    local args=""

    # Detect schema: <tml> or <fzf-layout>
    local root_xpath
    if tml_exists "$xml_file" "//tml"; then
        root_xpath="//tml/layout"
    elif tml_exists "$xml_file" "//fzf-layout"; then
        root_xpath="//fzf-layout"
    else
        echo "Error: Unknown schema" >&2
        return 1
    fi

    # Layout
    local direction height margin padding info no_select_1
    direction=$(tml_attr "$xml_file" "${root_xpath}/layout/@direction")
    [[ -z "$direction" ]] && direction=$(tml_attr "$xml_file" "${root_xpath}/@layout-direction")
    [[ -z "$direction" ]] && direction="reverse"

    height=$(tml_attr "$xml_file" "${root_xpath}/layout/@height")
    [[ -z "$height" ]] && height=$(tml_attr "$xml_file" "${root_xpath}/@layout-height")

    margin=$(tml_attr "$xml_file" "${root_xpath}/layout/@margin")
    [[ -z "$margin" ]] && margin=$(tml_attr "$xml_file" "${root_xpath}/@layout-margin")

    padding=$(tml_attr "$xml_file" "${root_xpath}/layout/@padding")
    [[ -z "$padding" ]] && padding=$(tml_attr "$xml_file" "${root_xpath}/@layout-padding")

    info=$(tml_attr "$xml_file" "${root_xpath}/layout/@info")
    [[ -z "$info" ]] && info=$(tml_attr "$xml_file" "${root_xpath}/@layout-info")
    no_select_1=$(tml_attr "$xml_file" "${root_xpath}/layout/@no-select-1")
    [[ -z "$no_select_1" ]] && no_select_1=$(tml_attr "$xml_file" "${root_xpath}/@no-select-1")

    args+="--layout $direction "
    [[ -n "$height" && "$height" != "100%" ]] && args+="--height $height "
    [[ -n "$margin" ]] && args+="--margin $margin "
    [[ -n "$padding" ]] && args+="--padding $padding "
    [[ "$no_select_1" == "true" ]] && args+="--no-select-1 "

    case "$info" in
        hidden) args+="--info=hidden " ;;
        inline) args+="--info=inline " ;;
    esac

    # Border
    local border_style border_label label_pos
    border_style=$(tml_attr "$xml_file" "${root_xpath}/border/@style")
    [[ -z "$border_style" ]] && border_style="rounded"
    border_label=$(tml_attr "$xml_file" "${root_xpath}/border/@label")
    label_pos=$(tml_attr "$xml_file" "${root_xpath}/border/@label-pos")

    args+="--border $border_style "
    if [[ -n "$border_label" ]]; then
        border_label=$(tml_eval "$border_label")
        border_label=$(tml_shell_escape "$border_label")
        args+="--border-label \"$border_label\" "
    fi
    [[ -n "$label_pos" ]] && args+="--border-label-pos $label_pos "

    # Prompt
    local prompt_text pointer
    prompt_text=$(tml_text "$xml_file" "${root_xpath}/prompt")
    pointer=$(tml_attr "$xml_file" "${root_xpath}/prompt/@pointer")

    if [[ -n "$prompt_text" ]]; then
        prompt_text=$(tml_eval "$prompt_text")
        prompt_text=$(tml_shell_escape "$prompt_text")
        args+="--prompt \"$prompt_text\" "
    fi
    if [[ -n "$pointer" ]]; then
        pointer=$(tml_eval "$pointer")
        pointer=$(tml_shell_escape "$pointer")
        args+="--pointer \"$pointer\" "
    fi

    # Header (raw or TML menu-bar)
    local header_content header_first
    header_content=$(tml_text "$xml_file" "${root_xpath}/header")
    header_first=$(tml_attr "$xml_file" "${root_xpath}/header/@first")
    [[ -z "$header_first" ]] && header_first="true"

    # Note: For TML with menu-bar, we don't include --header here
    # The caller should use tml_render_header separately
    if [[ -n "$header_content" ]]; then
        header_content=$(tml_eval "$header_content")
        # Escape special characters for safe embedding in double-quoted shell command
        header_content=$(tml_shell_escape "$header_content")
        args+="--header \"$header_content\" "
    fi
    [[ "$header_first" == "true" ]] && args+="--header-first "

    # Preview
    if tml_exists "$xml_file" "${root_xpath}/preview"; then
        local pos size wrap border script
        pos=$(tml_attr "$xml_file" "${root_xpath}/preview/@position")
        [[ -z "$pos" ]] && pos="right"
        size=$(tml_attr "$xml_file" "${root_xpath}/preview/@size")
        [[ -z "$size" ]] && size="50%"
        wrap=$(tml_attr "$xml_file" "${root_xpath}/preview/@wrap")
        border=$(tml_attr "$xml_file" "${root_xpath}/preview/@border")
        script=$(tml_attr "$xml_file" "${root_xpath}/preview/@script")

        local preview_spec="${pos}:${size}"
        [[ "$wrap" == "true" ]] && preview_spec+=":wrap"
        [[ -n "$border" ]] && preview_spec+=":${border}"

        args+="--preview-window '$preview_spec' "
        [[ -n "$script" ]] && args+="--preview '$(tml_eval "$script")' "
    fi

    # Colors
    if declare -F get_fzf_colors &>/dev/null; then
        local theme_colors
        theme_colors=$(get_fzf_colors 2>/dev/null || echo "")
        [[ -n "$theme_colors" ]] && args+="--color '$theme_colors' "
    else
        # Parse from XML
        local color_parts=""
        for color_name in fg bg hl "fg+" "bg+" "hl+" info prompt pointer marker spinner header border gutter; do
            local color_value
            color_value=$(tml_attr "$xml_file" "${root_xpath}/colors/color[@name='$color_name']/@value")
            if [[ -n "$color_value" ]]; then
                color_value=$(tml_eval "$color_value")
                [[ -n "$color_parts" ]] && color_parts+=","
                color_parts+="${color_name}:${color_value}"
            fi
        done
        [[ -n "$color_parts" ]] && args+="--color '$color_parts' "
    fi

    # Bindings
    local bindings_xpath="${root_xpath}/bindings"
    if tml_exists "$xml_file" "$bindings_xpath"; then
        local delimiter with_nth expect
        delimiter=$(tml_attr "$xml_file" "$bindings_xpath/@delimiter")
        with_nth=$(tml_attr "$xml_file" "$bindings_xpath/@with-nth")
        expect=$(tml_attr "$xml_file" "$bindings_xpath/@expect")

        [[ -n "$delimiter" ]] && args+="--delimiter '$delimiter' "
        [[ -n "$with_nth" ]] && args+="--with-nth $with_nth "

        # Individual binds
        local bind_count expect_keys=""
        bind_count=$(tml_count "$xml_file" "$bindings_xpath/bind")

        for ((i=1; i<=bind_count; i++)); do
            local key action return_code script reload
            key=$(tml_attr "$xml_file" "$bindings_xpath/bind[$i]/@key")
            action=$(tml_attr "$xml_file" "$bindings_xpath/bind[$i]/@action")
            return_code=$(tml_attr "$xml_file" "$bindings_xpath/bind[$i]/@return-code")
            script=$(tml_attr "$xml_file" "$bindings_xpath/bind[$i]/@script")

            [[ -z "$key" ]] && continue

            # Collect expect keys
            if [[ -n "$return_code" ]]; then
                [[ -n "$expect_keys" ]] && expect_keys+=","
                expect_keys+="$key"
            fi

            # Add bindings for actions
            case "$action" in
                execute)
                    [[ -n "$script" ]] && args+="--bind='${key}:execute(${script})' "
                    ;;
                abort|accept|toggle-preview|preview-down|preview-up)
                    args+="--bind='${key}:${action}' "
                    ;;
            esac
        done

        # Merge expect from attribute and collected
        [[ -n "$expect" && -n "$expect_keys" ]] && expect_keys="${expect},${expect_keys}"
        [[ -z "$expect" && -n "$expect_keys" ]] && expect="$expect_keys"
        [[ -n "$expect" ]] && args+="--expect '$expect' "

        TML_EXPECT_KEYS="$expect"
    fi

    TML_FZF_ARGS="$args"
}

# ═══════════════════════════════════════════════════════════════
# MENU BAR RENDERER (from V2)
# ═══════════════════════════════════════════════════════════════

_render_tab() {
    local xml_file="$1"
    local index="$2"

    local id shortcut shortcut_prefix label active
    id=$(tml_attr "$xml_file" "//tab-group/tab[$index]/@id")
    shortcut=$(tml_attr "$xml_file" "//tab-group/tab[$index]/@shortcut")
    shortcut_prefix=$(tml_attr "$xml_file" "//tab-group/tab[$index]/@shortcut-prefix")
    label=$(tml_text "$xml_file" "//tab-group/tab[$index]")
    active=$(tml_attr "$xml_file" "//tab-group/tab[$index]/@active")

    local is_active="false"
    [[ -n "$active" ]] && tml_eval_bool "$active" && is_active="true"

    local H_RESET=$'\e[0m'
    local H_BG_ACTIVE
    local H_BG_INACTIVE
    if declare -F hex_to_ansi_bg &>/dev/null; then
        H_BG_ACTIVE="$(hex_to_ansi_bg "${THEME_HEX_PILL_ACTIVE_BG:-${THEME_HEX_BG_SELECTION:-#5865f2}}")"
        H_BG_INACTIVE="$(hex_to_ansi_bg "${THEME_HEX_PILL_INACTIVE_BG:-${THEME_HEX_BG_SURFACE:-#414150}}")"
    else
        H_BG_ACTIVE=$'\e[48;2;88;101;242m'   # fallback: discord blue
        H_BG_INACTIVE=$'\e[48;2;65;65;80m'  # fallback: subtle gray
    fi
    local H_ACTIVE_FG
    if declare -F hex_to_ansi &>/dev/null; then
        H_ACTIVE_FG="$(hex_to_ansi "${THEME_HEX_PILL_ACTIVE_FG:-#ffffff}")"
    else
        H_ACTIVE_FG=$'\e[97m'
    fi
    local H_INACTIVE_FG
    local H_SHORTCUT_FG
    if declare -F hex_to_ansi &>/dev/null; then
        H_INACTIVE_FG="$(hex_to_ansi "${THEME_HEX_PILL_INACTIVE_FG:-${THEME_HEX_LAVENDER:-#C4B5FD}}")"
        H_SHORTCUT_FG="$(hex_to_ansi "${THEME_HEX_PILL_SHORTCUT_FG:-${THEME_HEX_GLOW:-#E879F9}}")"
    else
        H_INACTIVE_FG="${THEME_PILL_INACTIVE_FG:-${THEME_LAVENDER:-$'\e[38;2;196;181;253m'}}"
        H_SHORTCUT_FG="${THEME_PILL_SHORTCUT_FG:-${THEME_GLOW:-$'\e[38;2;245;184;255m'}}"
    fi
    local H_BOLD=$'\e[1m'
    local H_UL=$'\e[4m'
    local H_NO_UL=$'\e[24m'

    local formatted_label=""
    [[ -n "$shortcut_prefix" ]] && formatted_label="${shortcut_prefix}"
    local active_dot="${THEME_STR_ICON_ACTIVE_DOT-●}"

    if [[ "$is_active" == "true" ]]; then
        echo -ne "${H_BG_ACTIVE}${H_ACTIVE_FG} ${active_dot} ${formatted_label}${shortcut}${label#*$shortcut} ${H_RESET}"
    else
        echo -ne "${H_BG_INACTIVE}${H_INACTIVE_FG}${H_BOLD} ${formatted_label}${H_SHORTCUT_FG}${H_UL}${shortcut}${H_NO_UL}${H_INACTIVE_FG}${label#*$shortcut} ${H_RESET}"
    fi
}

_render_dropdown() {
    local xml_file="$1"
    local index="$2"

    local id shortcut label
    id=$(tml_attr "$xml_file" "//menu-bar/dropdown[$index]/@id")
    shortcut=$(tml_attr "$xml_file" "//menu-bar/dropdown[$index]/@shortcut")
    label=$(tml_text "$xml_file" "//menu-bar/dropdown[$index]")
    label=$(tml_eval "$label")

    local H_RESET=$'\e[0m'
    local H_BG_INACTIVE
    if declare -F hex_to_ansi_bg &>/dev/null; then
        H_BG_INACTIVE="$(hex_to_ansi_bg "${THEME_HEX_PILL_INACTIVE_BG:-${THEME_HEX_BG_SURFACE:-#414150}}")"
    else
        H_BG_INACTIVE=$'\e[48;2;65;65;80m'
    fi
    local H_INACTIVE_FG
    local H_SHORTCUT_FG
    if declare -F hex_to_ansi &>/dev/null; then
        H_INACTIVE_FG="$(hex_to_ansi "${THEME_HEX_PILL_INACTIVE_FG:-${THEME_HEX_LAVENDER:-#C4B5FD}}")"
        H_SHORTCUT_FG="$(hex_to_ansi "${THEME_HEX_PILL_SHORTCUT_FG:-${THEME_HEX_GLOW:-#E879F9}}")"
    else
        H_INACTIVE_FG="${THEME_PILL_INACTIVE_FG:-${THEME_LAVENDER:-$'\e[38;2;196;181;253m'}}"
        H_SHORTCUT_FG="${THEME_PILL_SHORTCUT_FG:-${THEME_GLOW:-$'\e[38;2;245;184;255m'}}"
    fi
    local H_BOLD=$'\e[1m'
    local H_UL=$'\e[4m'
    local H_NO_UL=$'\e[24m'

    local before_shortcut="" after_shortcut=""
    if [[ "$label" =~ ^(.*)${shortcut}(.*)$ ]]; then
        before_shortcut="${BASH_REMATCH[1]}"
        after_shortcut="${BASH_REMATCH[2]}"
    else
        before_shortcut="$label"
    fi

    echo -ne "${H_BG_INACTIVE}${H_INACTIVE_FG}${H_BOLD} ${before_shortcut}${H_SHORTCUT_FG}${H_UL}${shortcut}${H_NO_UL}${H_INACTIVE_FG}${after_shortcut} ${H_RESET}"
}

tml_render_header() {
    local xml_file="${1:-$TML_CURRENT_FILE}"
    local output=""

    # Check for menu-bar
    if tml_exists "$xml_file" "//menu-bar"; then
        # Logo
        local logo
        logo=$(tml_text "$xml_file" "//menu-bar/logo")
        if [[ -n "$logo" ]]; then
            logo=$(tml_eval "$logo")
            local H_PINK="${THEME_GLOW:-$'\e[38;2;232;121;249m'}"
            local H_PURPLE="${THEME_PURPLE:-$'\e[38;2;139;92;246m'}"
            local H_RESET=$'\e[0m'

            [[ "$logo" == *"TERMFLIX"* ]] && logo="${logo/TERMFLIX/${H_PINK}TERM${H_PURPLE}FLIX${H_RESET}}"
            output+="$logo  "
        fi

        # Tabs
        local tab_count
        tab_count=$(tml_count "$xml_file" "//tab-group/tab")
        for ((i=1; i<=tab_count; i++)); do
            output+="$(_render_tab "$xml_file" "$i") "
        done

        # Dropdowns
        local dropdown_count
        dropdown_count=$(tml_count "$xml_file" "//menu-bar/dropdown")
        for ((i=1; i<=dropdown_count; i++)); do
            output+="$(_render_dropdown "$xml_file" "$i") "
        done
    fi

    echo -ne "$output"
}

# ═══════════════════════════════════════════════════════════════
# MAIN API
# ═══════════════════════════════════════════════════════════════

tml_parse() {
    local tml_file="$1"

    # Handle both .tml and .xml
    if [[ ! -f "$tml_file" ]]; then
        # Try layouts directory
        if [[ -f "${TML_LAYOUTS_DIR}/${tml_file}" ]]; then
            tml_file="${TML_LAYOUTS_DIR}/${tml_file}"
        elif [[ -f "${TML_LAYOUTS_DIR}/${tml_file}.tml" ]]; then
            tml_file="${TML_LAYOUTS_DIR}/${tml_file}.tml"
        elif [[ -f "${TML_LAYOUTS_DIR}/${tml_file}.xml" ]]; then
            tml_file="${TML_LAYOUTS_DIR}/${tml_file}.xml"
        else
            echo "Error: File not found: $tml_file" >&2
            return 1
        fi
    fi

    TML_CURRENT_FILE="$tml_file"

    # Reset state
    for var in $(compgen -v TML_VAR_ 2>/dev/null || true); do
        unset "$var"
    done
    TML_FZF_ARGS=""
    TML_EXPECT_KEYS=""

    # Parse variables (TML only)
    _parse_variables "$tml_file"

    # Parse FZF args
    _parse_fzf_layout "$tml_file"
}

tml_get_fzf_args() {
    echo "$TML_FZF_ARGS"
}

tml_get_expect_keys() {
    echo "$TML_EXPECT_KEYS"
}

tml_get_options() {
    local xml_file="${1:-$TML_CURRENT_FILE}"
    local options_xpath="//fzf-layout/options/option"

    if [[ -z "$xml_file" ]] || [[ ! -f "$xml_file" ]]; then
        return 0
    fi

    # Fast path: extract options with grep/sed instead of xmllint for hardcoded options
    # This is instant compared to spawning multiple xmllint processes
    grep -E '<option>.*</option>' "$xml_file" 2>/dev/null | \
        sed 's/.*<option>\(.*\)<\/option>.*/\1/' | \
        while IFS= read -r opt; do
            [[ -z "$opt" ]] && continue
            opt=$(tml_eval "$opt")
            printf "%s\n" "$opt"
        done
}

tml_run_fzf() {
    local fzf_args
    fzf_args="$(tml_get_fzf_args)"

    local parsed_args=()
    if [[ -n "$fzf_args" ]]; then
        eval "parsed_args=( $fzf_args )"
    fi

    command fzf "${parsed_args[@]}" "$@"
}

# ═══════════════════════════════════════════════════════════════
# CLI
# ═══════════════════════════════════════════════════════════════

if [[ "${BASH_SOURCE[0]:-$0}" == "${0:-}" ]]; then
    case "${1:-}" in
        fzf-args)
            [[ -z "${2:-}" ]] && { echo "Usage: $0 fzf-args <file>"; exit 1; }
            tml_parse "$2"
            tml_get_fzf_args
            ;;
        render-header)
            [[ -z "${2:-}" ]] && { echo "Usage: $0 render-header <file>"; exit 1; }
            tml_parse "$2"
            tml_render_header
            echo ""
            ;;
        expect)
            [[ -z "${2:-}" ]] && { echo "Usage: $0 expect <file>"; exit 1; }
            tml_parse "$2"
            tml_get_expect_keys
            ;;
        --help|-h)
            echo "Unified TML Parser v2.0"
            echo ""
            echo "Usage:"
            echo "  $0 fzf-args <file>      Generate FZF command args"
            echo "  $0 render-header <file> Render menu-bar header"
            echo "  $0 expect <file>        Get expect keys"
            echo ""
            echo "As library:"
            echo "  source tml_parser.sh"
            echo "  tml_parse 'layout.tml'"
            echo "  fzf \$(tml_get_fzf_args) --header \"\$(tml_render_header)\""
            ;;
        *)
            echo "Use --help for usage" >&2
            exit 1
            ;;
    esac
fi

export -f tml_attr tml_text tml_count tml_exists tml_eval tml_eval_bool tml_shell_escape
export -f tml_parse tml_get_fzf_args tml_get_expect_keys tml_get_options tml_render_header tml_run_fzf
