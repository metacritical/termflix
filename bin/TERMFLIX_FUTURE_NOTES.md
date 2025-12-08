# Termflix Development Notes

## Overview

Charm/Charmbracelet-style theming has been applied to the termflix script.

---

## GUM/Charm-Style Color Palette (APPLIED)

The script uses terminal colors inspired by the Charm/gum CLI styling:

```bash
# Colors - Charm/Charmbracelet style palette (lines 1052-1074)
RED='\033[0;31m'
GREEN='\033[1;38;5;46m'       # Bright luminous green (like Charm selection highlight)
YELLOW='\033[1;38;5;220m'     # Warm yellow/gold
BLUE='\033[1;38;5;81m'        # Light blue (like Charm keywords)
CYAN='\033[1;38;5;87m'        # Bright cyan
MAGENTA='\033[1;38;5;213m'    # Vibrant magenta/pink (Charm accent - like ////// separators)
PURPLE='\033[1;38;5;135m'     # Medium purple (Charm border color)
PINK='\033[1;38;5;219m'       # Soft pink for secondary accents
BOLD='\033[1m'
RESET='\033[0m'
```

### Color Usage Patterns

| Color     | ANSI Code           | Typical Use                       |
|-----------|---------------------|-----------------------------------|
| MAGENTA   | `38;5;213`          | Headers, titles, accents, borders |
| PURPLE    | `38;5;135`          | Sidebar borders (│ character)     |
| GREEN     | `38;5;46`           | Success, selection, YTS source    |
| CYAN      | `38;5;87`           | Labels, info text, prompts        |
| YELLOW    | `38;5;220`          | Warnings, TPB source labels       |
| BLUE      | `38;5;81`           | EZTV source labels, keywords      |

---

## Sidebar Implementation

### Location
The sidebar is implemented around **lines 2218-2335** in the `draw_right_sidebar()` function.

### Key Details

```bash
# Sidebar Structure
local sidebar_width=35  # Fixed width
local sidebar_col=$((term_cols - 35))  # Position from right

# Draws vertical border line
for ((row=start_row; row<term_lines-2; row++)); do
    tput cup "$row" "$sidebar_col" 2>/dev/null || true
    echo -ne "${PURPLE}│${RESET}"
done
```

### Sidebar Content Sections
1. **Title**: "Termflix" in bold magenta
2. **Page Info**: "Page: X/Y" in cyan/green
3. **Results Count**: "Results: N" in cyan/green
4. **Selected Item Info** (when applicable):
   - Item name (truncated to 25 chars)
   - Source with color coding (YTS=green, TPB=yellow, EZTV=blue, 1337x=magenta)
   - Quality info
   - Seeds count

### Cursor Positioning Pattern
```bash
local sidebar_row=$((start_row + 1))
tput cup "$sidebar_row" $((sidebar_col + 2)) 2>/dev/null || true
echo -e "${BOLD}${MAGENTA}Termflix${RESET}"

sidebar_row=$((sidebar_row + 2))
tput cup "$sidebar_row" $((sidebar_col + 2)) 2>/dev/null || true
echo -e "${CYAN}Page:${RESET} ${GREEN}${current_page}/${total_pages}${RESET}"
```

### Status Bar
```bash
draw_status_bar() {
    # Positioned at bottom of screen
    local term_lines=$(tput lines)
    local term_cols=$(tput cols)
    tput cup $((term_lines - 1)) 0 2>/dev/null || true
    # Display controls and status info
}
```

---

## Inline Python Scripts

The script contains **multiple inline Python blocks** (heredocs) that could be extracted:

### 1. `group_results()` Function (around line 1584-1755)
- Purpose: Groups torrent results by title and year using Python hash tables
- Key imports: `sys, re, json, hashlib, collections.defaultdict`
- Contains functions:
  - `extract_year()` - Extracts year from torrent name
  - `normalize_title()` - Normalizes title for grouping
  - `compute_data_hash()` - Creates MD5 hash of metadata
  - `extract_seeds()` - Extracts seed count
  - `print_combined()` - Outputs grouped results

### 2. Search Functions (around line 1498-1580)
- `search_yts()` - Queries YTS API
- `search_tpb()` - Queries TPB proxies  
- Various API parsing scripts

### Extraction Plan
```
bin/
├── termflix              # Main script
└── scripts/
    ├── group_results.py  # Grouping logic
    ├── search_yts.py     # YTS API search
    ├── search_tpb.py     # TPB API search
    └── parse_config.py   # JSON config parsing
```

---

## Key Changes in Stashed Diff

### 1. UI Color Improvements
- Changed many `${YELLOW}` headers to `${MAGENTA}` for Charm consistency
- Changed `"Loading from cache..."` and similar to use magenta
- Changed parenthetical info `(...)` to square brackets `[...]` throughout

### 2. New Sidebar System
- Added `draw_right_sidebar()` function (147 new lines)
- Added `draw_status_bar()` function
- Main content width adjusted to account for sidebar
- `main_content_width=$((term_cols - sidebar_width - 1))`

### 3. Python Grouping Improvements
- Enhanced `normalize_title()` with more quality tags
- Added `compute_data_hash()` for `--data` flag support
- Better handling of TPB vs YTS seed/quality field differences

### 4. Debug Flag Additions
- New `--data` flag (same as `--debug`)
- Data hashes appended to output lines when enabled

### 5. Parentheses → Brackets Convention
Throughout the diff, many messages were changed from `(...)` to `[...]`:
- `(9273 seeds)` → `[9273 seeds]`
- `(Buffering...)` → `[Buffering...]`
- `(PID: 1234)` → `[PID: 1234]`

---

## Source Color Coding

```bash
case "$src" in
    YTS)   src_color="${GREEN}"   ;;
    TPB)   src_color="${YELLOW}"  ;;
    EZTV)  src_color="${BLUE}"    ;;
    1337x) src_color="${MAGENTA}" ;;
    *)     src_color="${CYAN}"    ;;
esac
```

---

## Future Work Recommendations

1. **Extract Python scripts** to separate files in `bin/scripts/` directory
2. **Use environment variables** to pass data between bash and Python
3. **Consider using `gum`** for interactive elements:
   - `gum choose` for multi-option selection
   - `gum spin` for spinners
   - `gum style` for styled text boxes
4. **Standardize on `[...]` brackets** for inline info consistently
5. **Test sidebar layout** at various terminal widths

---

## Git Stash Info

Changes were stashed with: `git stash push -m "Sidebar and gum colors WIP"`

To restore: `git stash pop` or `git stash apply`
