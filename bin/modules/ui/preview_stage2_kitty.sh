#!/usr/bin/env bash
#
# Stage 2 Preview Script - KITTY MODE
# -----------------------------------
# Used as the LEFT preview pane when picking a version.
# It renders a static copy of the movie catalog list so that
# Stage 2 appears visually identical to Stage 1, while the
# actual FZF picker (versions) lives on the right.

RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
MAGENTA=$'\033[38;5;213m'
CYAN=$'\033[38;5;87m'
GRAY=$'\033[38;5;241m'
GREEN=$'\033[38;5;46m'

selected_index="${STAGE2_SELECTED_INDEX:-}"

# Try environment first (if ever set), otherwise fall back
# to the snapshot files created by show_fzf_catalog.
header="${TERMFLIX_LAST_FZF_HEADER:-}"
catalog="${TERMFLIX_LAST_FZF_DISPLAY:-}"

if [[ -z "$header" ]]; then
    snap_dir="${TMPDIR:-/tmp}"
    snap_header_file="${snap_dir}/termflix_stage1_fzf_header.txt"
    [[ -f "$snap_header_file" ]] && header="$(cat "$snap_header_file" 2>/dev/null)"
fi

if [[ -z "$catalog" ]]; then
    snap_dir="${TMPDIR:-/tmp}"
    snap_file="${snap_dir}/termflix_stage1_fzf_display.txt"
    [[ -f "$snap_file" ]] && catalog="$(cat "$snap_file" 2>/dev/null)"
fi

# Header (matches Stage 1 style closely)
if [[ -n "$header" ]]; then
    echo -e "${BOLD}${CYAN}${header}${RESET}"
    echo
fi

# If we still have no catalog snapshot, just show an info message.
if [[ -z "$catalog" ]]; then
    echo -e "${DIM}No catalog snapshot available for Stage 2 preview.${RESET}"
    exit 0
fi

# Re-render the movie list.
# Each line of TERMFLIX_LAST_FZF_DISPLAY is:
#   "<display_text>|<index>|<full_result_data...>"
while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    IFS='|' read -r display idx _ <<< "$line"

    if [[ -n "$selected_index" && "$idx" == "$selected_index" ]]; then
        # Highlight the originally selected movie to mimic
        # the Stage 1 focused row (pointer + colored text).
        echo -e "${MAGENTA}▶ ${BOLD}${display}${RESET}"
    else
        echo "  $display"
    fi
done <<< "$catalog"

# Footer hint under the static list
echo
echo -e "${GRAY}────────────────────────────────────────${RESET}"
echo -e "${DIM}Ctrl+H to go back • Enter to stream${RESET}"

# Draw poster on the right to keep the
# same visual location as Stage 1 (kitty only).
if [[ "$TERM" == "xterm-kitty" ]] && command -v kitten &>/dev/null; then
    # Resolve script dir for fallback images
    SCRIPT_SOURCE="${BASH_SOURCE[0]}"
    while [ -L "$SCRIPT_SOURCE" ]; do
        SCRIPT_DIR_TMP="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
        SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
        [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR_TMP/$SCRIPT_SOURCE"
    done
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    FALLBACK_IMG="${SCRIPT_DIR%/bin/modules/ui}/lib/torrent/img/movie_night.jpg"

    poster_path="${STAGE2_POSTER:-}"
    [[ -z "$poster_path" || ! -f "$poster_path" ]] && poster_path="$FALLBACK_IMG"

    cols=$(tput cols 2>/dev/null || echo 120)
    preview_cols="${FZF_PREVIEW_COLUMNS:-$cols}"

    IMAGE_WIDTH=20
    IMAGE_HEIGHT=15

    # Compute the X offset where Stage 1's preview pane
    # would normally start. In Stage 2, the preview window
    # occupies the LEFT portion (preview_cols wide), so the
    # right-hand FZF list starts at column preview_cols.
    start_x=$preview_cols
    (( start_x < 0 )) && start_x=0

    # Draw poster roughly at row 2 of the right pane.
    if [[ -n "$poster_path" && -f "$poster_path" ]]; then
        kitten icat --transfer-mode=file --stdin=no \
            --place=${IMAGE_WIDTH}x${IMAGE_HEIGHT}@${start_x}x2 \
            --scale-up --align=left \
            "$poster_path" 2>/dev/null
    fi

    # Textual title / sources / available are now handled
    # via FZF's multi-line --header in the main picker.
fi
