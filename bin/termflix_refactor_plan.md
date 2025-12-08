# Termflix Refactor Plan v2: Pure Bash Modernization
# (Gum-free - all native bash/ANSI implementation)

## Overview
Complete refactor of termflix using pure bash with ANSI escape codes for modern UI.
No external UI dependencies - just standard tools (curl, jq, viu, tput).

---

## Feasibility Assessment

### ✅ What's Great About This Plan

| Aspect | Assessment |
|--------|------------|
| **Architecture** | Clean subdirectory structure (core/, api/, ui/, streaming/) - very logical |
| **Color Palette** | Well-thought-out 256-color scheme matching Charmbracelet aesthetics |
| **Viewport System** | Modern approach with lazy loading and infinite scroll |
| **Navigation** | Vim-style keybindings (j/k/g/G) are intuitive |
| **Timeline** | Realistic 14-day phasing with clear milestones |
| **No External Deps** | Pure bash - no Gum or other UI libraries needed |

### ⚠️ Key Design Decisions

1. **No Gum Dependency** - All UI built with native bash + ANSI escape codes
   - Pros: No installation required, works everywhere
   - Cons: More code to maintain, but we have full control

2. **Stremio-Style Sidebar Picker** - For torrent selection after choosing a movie
   - Large poster on left, scrollable torrent list on right
   - Replaces the old broken `show_sidebar_picker` with clean implementation

3. **Catalog Page Unchanged** - Keep existing grid layout
   - Already functional, no need to rewrite

4. **Signal Handling Built-in** - Proper SIGINT/SIGTERM handling
   - ^C returns to catalog instead of exiting
   - Clean process cleanup

### 📊 Overall Verdict

| Criterion | Score | Notes |
|-----------|-------|-------|
| Feasibility | **9/10** | Achievable with pure bash |
| Complexity | **Medium** | 2 weeks is realistic |
| Risk | **Low** | No external dependencies |
| Value | **High** | Significant UX improvement |

### ✅ Recommendation: PROCEED

This plan is 100% implementable with pure bash. No external UI dependencies required.

---


## Architecture

```
bin/
├── termflix                    # Main orchestration (~300 lines)
├── modules/
│   ├── core/
│   │   ├── config.sh          # Config management
│   │   ├── deps.sh            # Dependency checks
│   │   ├── errors.sh          # Error handling, SIGINT traps
│   │   └── colors.sh          # Charmbracelet color palette
│   ├── api/
│   │   ├── yts.sh             # YTS API
│   │   ├── tpb.sh             # ThePirateBay API
│   │   ├── eztv.sh            # EZTV API
│   │   └── tmdb.sh            # TMDB poster API
│   ├── ui/
│   │   ├── viewport.sh        # Paged content with j/k nav
│   │   ├── cards.sh           # Movie card rendering
│   │   ├── menus.sh           # Selection menus
│   │   ├── status.sh          # Status bar, progress
│   │   └── input.sh           # Keyboard input handling
│   └── streaming/
│       ├── torrent.sh         # Torrent streaming logic
│       └── players.sh         # mpv/vlc integration
└── scripts/                    # Python helpers (existing)
```

---

## Color Palette (colors.sh)

```bash
#!/usr/bin/env bash
# Charmbracelet-style color palette using 256-color ANSI

# Primary colors
C_GLOW=$'\033[38;5;212m'       # Vibrant pink (selection)
C_SUBTLE=$'\033[38;5;245m'     # Light gray (secondary)
C_MUTED=$'\033[38;5;241m'      # Muted gray (disabled)
C_SURFACE=$'\033[38;5;249m'    # Light background
C_CHARCOAL=$'\033[38;5;235m'   # Dark borders
C_CONTRAST=$'\033[38;5;15m'    # White (strong)
C_ERROR=$'\033[38;5;203m'      # Red
C_SUCCESS=$'\033[38;5;46m'     # Green
C_WARNING=$'\033[38;5;220m'    # Yellow
C_INFO=$'\033[38;5;81m'        # Cyan
C_PURPLE=$'\033[38;5;135m'     # Purple borders
C_PINK=$'\033[38;5;219m'       # Soft pink

# Text styles
BOLD=$'\033[1m'
DIM=$'\033[2m'
ITALIC=$'\033[3m'
UNDERLINE=$'\033[4m'
RESET=$'\033[0m'

# Source-specific colors
C_YTS=$'\033[38;5;46m'         # Green
C_TPB=$'\033[38;5;220m'        # Yellow
C_1337X=$'\033[38;5;213m'      # Magenta
C_EZTV=$'\033[38;5;81m'        # Cyan

# Convenience functions
styled() {
    local style="$1" text="$2"
    echo -e "${style}${text}${RESET}"
}

box_top()    { echo -e "${C_PURPLE}╭$( printf '─%.0s' $(seq 1 $1) )╮${RESET}"; }
box_bottom() { echo -e "${C_PURPLE}╰$( printf '─%.0s' $(seq 1 $1) )╯${RESET}"; }
box_line()   { echo -e "${C_PURPLE}│${RESET}$1${C_PURPLE}│${RESET}"; }
```

---

## Layout Clarification

### CATALOG PAGE (Existing - Keep As Is)
**Grid layout with multiple movies per row:**
```
╭────────────────╮  ╭────────────────╮  ╭────────────────╮
│    [POSTER]    │  │    [POSTER]    │  │    [POSTER]    │
│                │  │                │  │                │
│  The Matrix    │  │  Inception     │  │  Interstellar  │
│  ⭐8.7 1080p   │  │  ⭐8.8 1080p   │  │  ⭐8.6 1080p   │
╰────────────────╯  ╰────────────────╯  ╰────────────────╯
```
*This already works - keep the existing catalog display*

### TORRENT SELECTION PAGE (Stremio-Style Sidebar Picker)
**After selecting a movie from catalog:**
```
┌─────────────────────────────────────┬─────────────────────────────────────┐
│                                     │                                     │
│                                     │  Available Torrents                 │
│                                     │  ──────────────────                 │
│         [LARGE POSTER]              │  ➤ 7059 seeds   0⬇   1481MB   TPB  │ ← Selected (highlighted)
│                                     │    7059 seeds   0⬇   1481MB   TPB  │
│                                     │    7059 seeds   0⬇   1481MB   TPB  │
│                                     │    7059 seeds   0⬇   1481MB   TPB  │
│                                     │    7059 seeds   0⬇   1481MB   TPB  │
│                                     │    7059 seeds   0⬇   1481MB   TPB  │
│                                     │    7059 seeds   0⬇   1481MB   TPB  │
│                                     │    2500 seeds   0⬇   1.4GB    YTS  │
│                                     │     850 seeds   0⬇   850MB    YTS  │
│    NO OTHER CHOICE                  │                                     │
│                                     │                                     │
├─────────────────────────────────────┴─────────────────────────────────────┤
│ Predator Badlands 2025 1080p HDRip HEVC x265 BONE                        │
│ 10 sources                                                                │
├───────────────────────────────────────────────────────────────────────────┤
│         ↑↓ navigate  •  enter select  •  q quit                          │
└───────────────────────────────────────────────────────────────────────────┘
```

**Key Features:**
- Left panel (~40-45%): Large poster with movie title at bottom
- Right panel (~55-60%): Scrollable torrent list with vim-style navigation
- Selected row highlighted (bright color, ➤ indicator)
- Each row shows: seeds | leechers | size | source
- Source color-coded: YTS=green, TPB=yellow, 1337x=magenta, EZTV=cyan
- Footer: Movie full name, source count, navigation hints

### sidebar_picker.sh - Implementation
```bash
#!/usr/bin/env bash
# Stremio-style sidebar picker for torrent selection

show_sidebar_picker() {
    local movie_name="$1"
    local poster_path="$2"
    shift 2
    local -a torrents=("$@")
    
    local term_cols=$(tput cols)
    local term_rows=$(tput lines)
    
    # Layout: 45% left (poster), 55% right (list)
    local left_width=$((term_cols * 45 / 100))
    local right_start=$((left_width + 1))
    local right_width=$((term_cols - right_start - 2))
    
    # State
    local selected=0
    local scroll_offset=0
    local visible_items=$((term_rows - 10))
    local num_items=${#torrents[@]}
    
    # Save terminal state
    tput smcup      # Alternate screen
    tput civis      # Hide cursor
    stty -echo -icanon min 1 time 0
    
    trap '_sidebar_cleanup' EXIT INT TERM
    
    _sidebar_cleanup() {
        stty echo icanon 2>/dev/null
        tput cnorm 2>/dev/null
        tput rmcup 2>/dev/null
    }
    
    _draw_sidebar() {
        clear
        
        # ─── LEFT PANEL: POSTER ───
        if [[ -f "$poster_path" ]] && command -v viu &>/dev/null; then
            tput cup 2 2
            viu -w $((left_width - 4)) -h $((term_rows - 12)) "$poster_path" 2>/dev/null
        fi
        
        # Movie title at bottom of left panel
        local title_row=$((term_rows - 6))
        tput cup $title_row 2
        echo -ne "${C_GLOW}${BOLD}${movie_name:0:$((left_width-4))}${RESET}"
        
        # ─── DIVIDER ───
        for ((r=1; r<term_rows-3; r++)); do
            tput cup $r $left_width
            echo -ne "${C_PURPLE}│${RESET}"
        done
        
        # ─── RIGHT PANEL: TORRENT LIST ───
        tput cup 1 $right_start
        echo -ne "${BOLD}${C_GLOW}Available Torrents${RESET}"
        
        tput cup 2 $right_start
        echo -ne "${C_PURPLE}$(printf '─%.0s' $(seq 1 $((right_width-2))))${RESET}"
        
        local list_start_row=4
        for ((i=0; i<visible_items && i+scroll_offset<num_items; i++)); do
            local idx=$((i + scroll_offset))
            local row=$((list_start_row + i))
            
            tput cup $row $right_start
            printf "%*s" "$right_width" ""  # Clear line
            tput cup $row $right_start
            
            # Parse torrent: source|quality|seeds|size
            IFS='|' read -r src quality seeds size <<< "${torrents[$idx]}"
            
            # Source color
            local src_color="${C_SUBTLE}"
            case "$src" in
                YTS)   src_color="${C_YTS}" ;;
                TPB)   src_color="${C_TPB}" ;;
                1337x) src_color="${C_1337X}" ;;
                EZTV)  src_color="${C_EZTV}" ;;
            esac
            
            if [[ $idx -eq $selected ]]; then
                # Selected row - highlighted
                echo -ne "${C_GLOW}➤ ${BOLD}"
                printf "%-6s seeds   %-4s   %-8s ${src_color}%-6s${RESET}" \
                    "$seeds" "0⬇" "$size" "$src"
            else
                echo -ne "  ${C_SUBTLE}"
                printf "%-6s seeds   %-4s   %-8s ${src_color}%-6s${RESET}" \
                    "$seeds" "0⬇" "$size" "$src"
            fi
        done
        
        # ─── FOOTER ───
        local footer_row=$((term_rows - 3))
        tput cup $footer_row 0
        echo -ne "${C_PURPLE}$(printf '─%.0s' $(seq 1 $term_cols))${RESET}"
        
        tput cup $((footer_row + 1)) 2
        echo -ne "${C_SUBTLE}${num_items} sources${RESET}"
        
        # Navigation hints (centered)
        local hints="↑↓ navigate  •  enter select  •  q quit"
        local hints_col=$(( (term_cols - ${#hints}) / 2 ))
        tput cup $((footer_row + 2)) $hints_col
        echo -ne "${C_MUTED}${hints}${RESET}"
    }
    
    # Main loop
    _draw_sidebar
    while true; do
        IFS= read -rsn1 key
        
        case "$key" in
            j|J)  # Down
                if [[ $selected -lt $((num_items - 1)) ]]; then
                    ((selected++))
                    [[ $((selected - scroll_offset)) -ge $visible_items ]] && ((scroll_offset++))
                    _draw_sidebar
                fi
                ;;
            k|K)  # Up
                if [[ $selected -gt 0 ]]; then
                    ((selected--))
                    [[ $selected -lt $scroll_offset ]] && ((scroll_offset--))
                    _draw_sidebar
                fi
                ;;
            '')  # Enter - select
                _sidebar_cleanup
                echo "$selected"
                return 0
                ;;
            q|Q)  # Quit
                _sidebar_cleanup
                return 1
                ;;
            $'\x1b')  # Escape sequences
                read -rsn2 -t 0.1 seq
                case "$seq" in
                    '[A') # Up arrow
                        if [[ $selected -gt 0 ]]; then
                            ((selected--))
                            [[ $selected -lt $scroll_offset ]] && ((scroll_offset--))
                            _draw_sidebar
                        fi
                        ;;
                    '[B') # Down arrow
                        if [[ $selected -lt $((num_items - 1)) ]]; then
                            ((selected++))
                            [[ $((selected - scroll_offset)) -ge $visible_items ]] && ((scroll_offset++))
                            _draw_sidebar
                        fi
                        ;;
                esac
                ;;
        esac
    done
}
```

---

## UI Components (Native Bash)

### viewport.sh - Scrollable Content
```bash
#!/usr/bin/env bash
# Viewport with j/k navigation, pagination, lazy loading

declare -g VIEWPORT_ITEMS=()
declare -g VIEWPORT_CURSOR=0
declare -g VIEWPORT_OFFSET=0
declare -g VIEWPORT_HEIGHT=0
declare -g VIEWPORT_PAGE=1

viewport_init() {
    VIEWPORT_HEIGHT=$(($(tput lines) - 6))  # Reserve for header/footer
    VIEWPORT_CURSOR=0
    VIEWPORT_OFFSET=0
    stty -echo -icanon min 1 time 0 2>/dev/null
    tput civis  # Hide cursor
    trap 'viewport_cleanup' EXIT INT TERM
}

viewport_cleanup() {
    stty echo icanon 2>/dev/null
    tput cnorm  # Show cursor
}

viewport_render() {
    local start_row=2
    local visible_items=$((VIEWPORT_HEIGHT / 4))  # 4 lines per card
    
    # Clear viewport area
    for ((i=start_row; i<start_row+VIEWPORT_HEIGHT; i++)); do
        tput cup $i 0
        tput el
    done
    
    # Render visible items
    for ((i=0; i<visible_items && i+VIEWPORT_OFFSET<${#VIEWPORT_ITEMS[@]}; i++)); do
        local idx=$((i + VIEWPORT_OFFSET))
        local row=$((start_row + i * 4))
        local is_selected=$([[ $idx -eq $VIEWPORT_CURSOR ]] && echo 1 || echo 0)
        render_card "$row" "${VIEWPORT_ITEMS[$idx]}" "$is_selected"
    done
    
    # Render status bar
    render_status_bar
}

viewport_handle_key() {
    local key
    IFS= read -rsn1 key
    
    case "$key" in
        j|J) viewport_move_down ;;
        k|K) viewport_move_up ;;
        n|N) viewport_next_page ;;
        p|P) viewport_prev_page ;;
        g)   viewport_go_top ;;
        G)   viewport_go_bottom ;;
        '')  viewport_select ;;  # Enter
        q|Q) return 1 ;;
        $'\x1b')  # Escape sequences
            read -rsn2 -t 0.1 seq
            case "$seq" in
                '[A') viewport_move_up ;;    # Up arrow
                '[B') viewport_move_down ;;  # Down arrow
                '[5') viewport_prev_page ;;  # Page Up
                '[6') viewport_next_page ;;  # Page Down
            esac
            ;;
    esac
    return 0
}

viewport_move_down() {
    local max=$((${#VIEWPORT_ITEMS[@]} - 1))
    if [[ $VIEWPORT_CURSOR -lt $max ]]; then
        ((VIEWPORT_CURSOR++))
        local visible=$((VIEWPORT_HEIGHT / 4))
        if [[ $((VIEWPORT_CURSOR - VIEWPORT_OFFSET)) -ge $visible ]]; then
            ((VIEWPORT_OFFSET++))
        fi
    fi
}

viewport_move_up() {
    if [[ $VIEWPORT_CURSOR -gt 0 ]]; then
        ((VIEWPORT_CURSOR--))
        if [[ $VIEWPORT_CURSOR -lt $VIEWPORT_OFFSET ]]; then
            ((VIEWPORT_OFFSET--))
        fi
    fi
}
```

### menus.sh - Selection Menus
```bash
#!/usr/bin/env bash
# Native bash selection menu (replaces numbered input)

select_from_list() {
    local title="$1"
    shift
    local options=("$@")
    local selected=0
    local max=$((${#options[@]} - 1))
    
    # Save terminal state
    tput smcup
    tput civis
    stty -echo -icanon min 1 time 0
    
    trap 'tput rmcup; tput cnorm; stty echo icanon' EXIT INT TERM
    
    while true; do
        clear
        echo -e "${C_GLOW}${BOLD}$title${RESET}\n"
        
        for i in "${!options[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "  ${C_GLOW}➤${RESET} ${BOLD}${options[$i]}${RESET}"
            else
                echo -e "    ${C_SUBTLE}${options[$i]}${RESET}"
            fi
        done
        
        echo -e "\n${C_SUBTLE}j/k: move  Enter: select  q: cancel${RESET}"
        
        IFS= read -rsn1 key
        case "$key" in
            j|J|'[B') [[ $selected -lt $max ]] && ((selected++)) ;;
            k|K|'[A') [[ $selected -gt 0 ]] && ((selected--)) ;;
            '') 
                tput rmcup; tput cnorm; stty echo icanon
                echo "$selected"
                return 0
                ;;
            q|Q)
                tput rmcup; tput cnorm; stty echo icanon
                return 1
                ;;
            $'\x1b')
                read -rsn2 -t 0.1 seq
                case "$seq" in
                    '[A') [[ $selected -gt 0 ]] && ((selected--)) ;;
                    '[B') [[ $selected -lt $max ]] && ((selected++)) ;;
                esac
                ;;
        esac
    done
}

# Usage:
# idx=$(select_from_list "Select Version" "${versions[@]}")
# if [[ $? -eq 0 ]]; then
#     echo "Selected: ${versions[$idx]}"
# fi
```

### cards.sh - Movie Card Rendering
```bash
#!/usr/bin/env bash
# Two-column card: poster on left, details on right

render_card() {
    local row="$1"
    local data="$2"
    local selected="$3"
    
    # Parse data: title|year|quality|seeds|rating|sources|poster_path
    IFS='|' read -r title year quality seeds rating sources poster_path <<< "$data"
    
    local term_cols=$(tput cols)
    local card_width=$((term_cols - 4))
    local poster_cols=22
    local text_start=$((poster_cols + 3))
    
    # Selection indicator
    local sel_char=" "
    local sel_color=""
    if [[ "$selected" == "1" ]]; then
        sel_char="▶"
        sel_color="${C_GLOW}"
    fi
    
    # Row 1: Top border
    tput cup $row 0
    echo -ne "${sel_color}${sel_char}${RESET} ${C_PURPLE}╭$(printf '─%.0s' $(seq 1 $card_width))╮${RESET}"
    
    # Row 2-4: Poster area (left) + Title (right)
    local poster_row=$((row + 1))
    
    # Display poster using viu or placeholder
    if [[ -f "$poster_path" ]] && command -v viu &>/dev/null; then
        tput cup $poster_row 3
        viu -w 20 -h 6 "$poster_path" 2>/dev/null
    else
        # Text placeholder
        for i in {0..5}; do
            tput cup $((poster_row + i)) 3
            if [[ $i -eq 2 ]]; then
                echo -ne "${C_MUTED}   🎬 No Poster   ${RESET}"
            else
                echo -ne "${C_MUTED}                    ${RESET}"
            fi
        done
    fi
    
    # Right side: Title and details
    tput cup $poster_row $text_start
    echo -ne "${sel_color}${BOLD}${title:0:40}${RESET}"
    [[ ${#title} -gt 40 ]] && echo -ne "..."
    
    tput cup $((poster_row + 1)) $text_start
    echo -ne "${C_SUBTLE}(${year})${RESET} │ ${C_INFO}${quality}${RESET}"
    [[ -n "$rating" && "$rating" != "N/A" ]] && echo -ne " │ ⭐ ${rating}"
    
    tput cup $((poster_row + 2)) $text_start
    format_source_tags "$sources"
    
    tput cup $((poster_row + 3)) $text_start
    echo -ne "${C_WARNING}🔥 ${seeds} seeds${RESET}"
    
    # Bottom border
    tput cup $((row + 5)) 0
    echo -ne "  ${C_PURPLE}╰$(printf '─%.0s' $(seq 1 $card_width))╯${RESET}"
}

format_source_tags() {
    local sources="$1"
    IFS='^' read -ra src_arr <<< "$sources"
    for src in "${src_arr[@]}"; do
        case "$src" in
            YTS)   echo -ne "${C_YTS}[YTS]${RESET} " ;;
            TPB)   echo -ne "${C_TPB}[TPB]${RESET} " ;;
            1337x) echo -ne "${C_1337X}[1337x]${RESET} " ;;
            EZTV)  echo -ne "${C_EZTV}[EZTV]${RESET} " ;;
        esac
    done
}
```

### errors.sh - Error Handling & Signals
```bash
#!/usr/bin/env bash
# Unified error handling and signal management

declare -g TERMFLIX_CLEANUP_FUNCS=()
declare -g TERMFLIX_CHILD_PIDS=()

register_cleanup() {
    TERMFLIX_CLEANUP_FUNCS+=("$1")
}

register_child_pid() {
    TERMFLIX_CHILD_PIDS+=("$1")
}

termflix_cleanup() {
    # Kill child processes
    for pid in "${TERMFLIX_CHILD_PIDS[@]}"; do
        kill -TERM "$pid" 2>/dev/null
        sleep 0.5
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    done
    
    # Run cleanup functions
    for func in "${TERMFLIX_CLEANUP_FUNCS[@]}"; do
        $func 2>/dev/null
    done
    
    # Restore terminal
    stty echo icanon 2>/dev/null
    tput cnorm 2>/dev/null
    tput rmcup 2>/dev/null
}

handle_sigint() {
    echo ""
    echo -e "${C_WARNING}⚠ Cancelled by user${RESET}"
    termflix_cleanup
    exit 130
}

handle_sigterm() {
    termflix_cleanup
    exit 143
}

setup_signal_handlers() {
    trap 'handle_sigint' INT
    trap 'handle_sigterm' TERM
    trap 'termflix_cleanup' EXIT
}

show_error() {
    echo -e "${C_ERROR}✗ Error:${RESET} $1" >&2
}

show_warning() {
    echo -e "${C_WARNING}⚠ Warning:${RESET} $1" >&2
}

show_success() {
    echo -e "${C_SUCCESS}✓${RESET} $1"
}

show_info() {
    echo -e "${C_INFO}ℹ${RESET} $1"
}
```

### status.sh - Status Bar & Progress
```bash
#!/usr/bin/env bash
# Status bar and progress indicators

render_status_bar() {
    local term_lines=$(tput lines)
    local term_cols=$(tput cols)
    local status_row=$((term_lines - 1))
    
    tput cup $status_row 0
    
    # Background bar
    echo -ne "\033[48;5;235m"  # Dark background
    printf "%-${term_cols}s" ""
    
    # Left: Page info
    tput cup $status_row 1
    echo -ne "${C_SUBTLE}Page ${VIEWPORT_PAGE}${RESET}"
    
    # Center: Item count
    local center=$((term_cols / 2 - 10))
    tput cup $status_row $center
    echo -ne "${C_SUBTLE}${VIEWPORT_CURSOR}/${#VIEWPORT_ITEMS[@]} items${RESET}"
    
    # Right: Key hints
    tput cup $status_row $((term_cols - 35))
    echo -ne "${C_MUTED}j/k:move n/p:page Enter:select q:quit${RESET}"
    
    echo -ne "\033[0m"  # Reset background
}

show_spinner() {
    local pid="$1"
    local message="${2:-Loading...}"
    local chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${C_GLOW}${chars[$i]}${RESET} ${C_SUBTLE}${message}${RESET}"
        i=$(( (i + 1) % ${#chars[@]} ))
        sleep 0.1
    done
    printf "\r${C_SUCCESS}✓${RESET} ${message}\n"
}

show_progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-30}"
    
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r${C_PURPLE}[${RESET}"
    printf "${C_GLOW}%${filled}s${RESET}" | tr ' ' '█'
    printf "${C_MUTED}%${empty}s${RESET}" | tr ' ' '░'
    printf "${C_PURPLE}]${RESET} ${C_SUBTLE}%3d%%${RESET}" "$percent"
}
```

### input.sh - Search Input
```bash
#!/usr/bin/env bash
# Native search input with styling

read_search_query() {
    local placeholder="${1:-Search movies, TV shows...}"
    
    echo -ne "${C_GLOW}🔍 ${RESET}"
    echo -ne "${C_SUBTLE}${placeholder}${RESET}"
    
    # Move cursor back to start of input
    tput cub ${#placeholder}
    
    # Read input (with echo)
    local query=""
    read -r query
    
    echo "$query"
}
```

---

## Implementation Phases (Revised)

### Phase 1: Core Foundation (Days 1-3)
- [ ] Create new module directory structure
- [ ] Implement colors.sh with full palette
- [ ] Implement errors.sh with signal handlers
- [ ] Create thin main orchestration script
- [ ] Migrate existing code to new structure

### Phase 2: UI Components (Days 4-7)
- [ ] Implement viewport.sh with j/k navigation
- [ ] Implement menus.sh selection system
- [ ] Implement cards.sh two-column layout
- [ ] Implement status.sh bar and spinners

### Phase 3: Integration (Days 8-10)
- [ ] Connect API modules to viewport
- [ ] Implement catalog page with pagination
- [ ] Implement grouped torrents selection
- [ ] Wire up streaming module

### Phase 4: Polish (Days 11-14)
- [ ] Edge case handling
- [ ] Performance optimization
- [ ] Testing on various terminals
- [ ] Documentation

---

## Key Differences from v1 Plan

| Aspect | v1 (Gum) | v2 (Native) |
|--------|----------|-------------|
| Dependencies | Requires Gum | No new deps |
| Performance | Process per style | Inline ANSI |
| Fallback | Needed fallbacks | Self-contained |
| Portability | Go/Gum install | Pure bash |
| Complexity | Higher | Lower |

---

## Testing Strategy

```bash
# Test color support
test_colors() {
    for i in {0..255}; do
        printf "\033[38;5;${i}m%3d " "$i"
        [[ $((i % 16)) -eq 15 ]] && echo ""
    done
}

# Test in different terminals
# - iTerm2
# - Terminal.app
# - Alacritty
# - Kitty
# - tmux

# Test signal handling
# - Ctrl+C during operations
# - Process kill during streaming
```

This plan is 100% implementable with pure bash - no external UI dependencies.