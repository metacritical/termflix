# TML/XML-Based UI Layout System for FZF

A declarative layout DSL for defining fzf-based terminal UI layouts. This system separates UI definitions from business logic, making layouts easier to maintain, modify, and version control.

Termflix currently supports two layout parsers:
- Primary (runtime): `modules/ui/tml/parser/tml_parser.sh` (supports `<fzf-layout>` and `<tml>`)
- Legacy: `modules/ui/lib/ui_parser.sh` (kept for older docs/tests)

## Overview

Instead of hardcoding fzf command-line arguments in bash scripts:

```bash
# Before: Hardcoded fzf calls
selection=$(printf "%s" "$data" | fzf \
    --ansi \
    --layout=reverse \
    --border=rounded \
    --margin=1 \
    --padding=1 \
    --header="$menu_header" \
    --preview="$preview_script" \
    --preview-window=left:55%:wrap:border-right \
    --color="fg:#6b7280,bg:#1e1e2e,hl:#818cf8,..." \
    --bind="ctrl-e:execute($season_picker_script)+reload(...)")
```

Define layouts declaratively in XML:

```xml
<fzf-layout id="episode-picker" name="Episode Picker">
  <layout direction="reverse" height="100%" margin="1" padding="1" info="default"/>
  <preview position="left" size="55%" wrap="true" border="border-right"
            script="${UI_DIR}/pickers/preview_episode.sh &quot;$ep_no&quot;"
            delimiter="|" with-nth="2"/>
  <header first="true">Pick Episode - [$CLEAN_TITLE] Season ${SEASON_NUM} →</header>
  <border style="rounded" label=" ⌨ Enter:Select  Ctrl+E:Season  Ctrl+H:Back " label-pos="bottom"/>
  <prompt pointer="➤">&gt;</prompt>
  <colors theme="catppuccin">...</colors>
  <bindings expect="enter,ctrl-e,ctrl-s,ctrl-h,ctrl-l,esc"/>
</fzf-layout>
```

## Directory Structure

```
modules/ui/
├── catalog/
│   ├── fzf_catalog.sh             # Main catalog UI
│   └── preview_fzf.sh             # Catalog preview pane
├── debug/
│   └── debug_*.sh                 # Debug helpers
├── examples/
│   └── example_usage.sh           # Usage examples
├── schema/
│   └── layout_schema.xml          # XSD schema for validation
├── layouts/
│   ├── main-catalog.xml           # Stage 1 base layout args
│   ├── main-catalog.tml           # Stage 1 header (menu-bar)
│   ├── episode-picker.xml         # Episode selection
│   ├── season-picker.xml          # Season selection popup
│   ├── version-picker.xml         # Quality/source picker
│   ├── movie-version-picker.xml   # Movie version selector
│   ├── buffer-ui.xml              # Buffer status UI
│   └── simple-menu.xml            # Simple dropdown menus
├── lib/
│   ├── ui_parser.sh               # XML parser and fzf command builder
│   ├── image_display.sh           # Image display helpers
│   ├── logo.sh                    # Header logo helpers
│   ├── status.sh                  # Status and progress UI
│   └── help.sh                    # Help screen UI
├── pickers/
│   ├── episode_picker.sh          # Episode selector
│   ├── preview_episode.sh         # Episode preview pane
│   └── season_picker.sh           # Season selector
├── previews/
│   └── preview_stage2.sh          # Stage 2 preview pane
└── tests/
    └── test_*.sh                  # Local test scripts

modules/ui/tml/
└── parser/
    └── tml_parser.sh              # Primary parser used by Termflix
```

## Usage

### Basic Usage

```bash
# Source the parser (primary)
source modules/ui/tml/parser/tml_parser.sh

# Parse a layout
tml_parse modules/ui/layouts/episode-picker.xml

# Run fzf with parsed args
selection=$(printf "%s" "$data" | tml_run_fzf)

# Or just build the arguments
args=$(tml_get_fzf_args)
selection=$(printf "%s" "$data" | fzf $args)
```

### With Extra Arguments

```bash
tml_parse modules/ui/layouts/simple-menu.xml
selection=$(printf "%s" "$data" | tml_run_fzf \
    --prompt="Choose > " \
    --header="Custom Header")
```

### CLI Tools

```bash
# Generate fzf args for a layout
modules/ui/tml/parser/tml_parser.sh fzf-args modules/ui/layouts/main-catalog.xml
```

## XML Schema Reference

### Root Element

```xml
<fzf-layout id="unique-id" name="Human Readable Name">
  <!-- layout configuration -->
</fzf-layout>
```

### Layout Configuration

```xml
<layout direction="reverse|default"
         height="100%"
         margin="1"
         padding="1"
         info="default|hidden|inline"/>
```

| Attribute | Values | Description |
|-----------|--------|-------------|
| `direction` | `reverse`, `default` | List scrolling direction |
| `height` | `N%`, `N` | Window height (default: 100%) |
| `margin` | `N`, `X%,Y%` | Margin around window |
| `padding` | `N` | Padding inside window |
| `info` | `default`, `hidden`, `inline` | Info display mode |

### Preview Window

```xml
<preview position="left|right|up|down|hidden"
          size="50%"
          wrap="true"
          border="border-left"
          script="/path/to/preview.sh {args}"
          delimiter="|"
          with-nth="2"/>
```

| Attribute | Values | Description |
|-----------|--------|-------------|
| `position` | `left`, `right`, `up`, `down`, `hidden` | Preview position |
| `size` | `N%` | Preview pane width/height |
| `wrap` | `true`, `false` | Enable text wrapping |
| `border` | `border-left`, `border-right`, etc. | Border style |
| `script` | path | Preview script to execute |
| `delimiter` | char | Field delimiter for preview args |
| `with-nth` | N | Which fields to show as list items |

### Header

```xml
<header first="true">Header Text</header>
```

| Attribute | Values | Description |
|-----------|--------|-------------|
| `first` | `true`, `false` | Show header above list |

### Border

```xml
<border style="rounded"
         label=" ⌨ Enter:Select "
         label-pos="bottom"/>
```

| Attribute | Values | Description |
|-----------|--------|-------------|
| `style` | `rounded`, `sharp`, `bold`, `block`, `thinline`, `double`, `hidden` | Border style |
| `label` | text | Border label text |
| `label-pos` | `top`, `bottom`, `left`, `right` | Label position |

### Prompt

```xml
<prompt pointer="➤">&gt; Prompt Text</prompt>
```

| Attribute | Values | Description |
|-----------|--------|-------------|
| `pointer` | text | Cursor pointer character |

### Colors

```xml
<colors theme="default">
  <color name="fg" value="#6b7280"/>
  <color name="bg" value="#1e1e2e"/>
  <color name="hl" value="#818cf8"/>
  <color name="fg+" value="#ffffff"/>
  <color name="bg+" value="#5865f2"/>
  <color name="hl+" value="#c4b5fd"/>
  <color name="info" value="#6b7280"/>
  <color name="prompt" value="#5eead4"/>
  <color name="pointer" value="#818cf8"/>
  <color name="marker" value="#818cf8"/>
  <color name="spinner" value="#818cf8"/>
  <color name="header" value="#a78bfa"/>
  <color name="border" value="#5865f2"/>
  <color name="gutter" value="#1e1e2e"/>
</colors>
```

**Dynamic color values** (using shell variables):

```xml
<color name="pointer" value="${THEME_HEX_GLOW:-#e879f9}"/>
```

### Key Bindings

```xml
<bindings delimiter="&tab;" with-nth="1" expect="enter,ctrl-e,esc">
  <bind key="ctrl-e" action="execute"
        script="${UI_DIR}/pickers/season_picker.sh {2..}"
        reload="true"/>
  <bind key="ctrl-/" action="toggle-preview"/>
  <bind key="ctrl-h" action="abort"/>
  <bind key="enter" action="accept"/>
  <bind key="ctrl-o" return-code="101"/>
</bindings>
```

| Binding Attributes |
|-------------------|
| `key` | Key combination (e.g., `ctrl-e`, `enter`, `esc`) |
| `action` | `execute`, `abort`, `accept`, `toggle-preview`, `preview-down`, `preview-up` |
| `script` | Script path for `execute` action |
| `reload` | `true`, `false` - Reload list after execute |
| `return-code` | Numeric code to return for main loop |

## Migration Guide

### Before (Hardcoded)

```bash
selection=$(printf "%s" "$episode_list" | fzf \
    --height=100% \
    --layout=reverse \
    --border=rounded \
    --margin=1 \
    --padding=1 \
    --delimiter='|' \
    --with-nth=2 \
    --pointer='➤' \
    --prompt="> " \
    --header="Pick Episode - [$CLEAN_TITLE] Season ${SEASON_NUM} →" \
    --header-first \
    --info=default \
    --border-label=" ⌨ Enter:Select  Ctrl+E:Season  Ctrl+H:Back " \
    --border-label-pos=bottom \
    --expect=enter,ctrl-e,ctrl-s,ctrl-h,ctrl-l,esc \
    --ansi \
    --color="$(get_fzf_colors)" \
    --preview-window=left:55%:wrap:border-right \
    --preview "ep_no=\$(echo {} | cut -d'|' -f1); ${UI_DIR}/pickers/preview_episode.sh \"\$ep_no\"")

KEY=$(echo "$RESULTS" | head -1)
SELECTED=$(echo "$RESULTS" | tail -1)
```

### After (XML + Parser)

```bash
# Define layout in episode_picker.xml (already done)

# Use in script
source "${UI_DIR}/lib/ui_parser.sh"
export CLEAN_TITLE="Series Name"
export SEASON_NUM="1"
export UI_DIR="/path/to/modules/ui"

RESULTS=$(printf "%s" "$episode_list" | run_fzf_layout "episode-picker")

KEY=$(echo "$RESULTS" | head -1)
SELECTED=$(echo "$RESULTS" | tail -1)
```

### Advantages

1. **Declarative**: UI is defined, not constructed
2. **Reusable**: Share layouts across scripts
3. **Maintainable**: One place to modify UI
4. **Versionable**: XML diffs are clearer than bash code
5. **Theming**: Centralized color management
6. **Validation**: Schema validation possible
7. **Tooling**: Can build editors/visualizers

## Environment Variables

Layouts can reference environment variables:

```xml
<header>[$VAR_NAME]</header>
<prompt>$ANOTHER_VAR</prompt>
<color name="pointer" value="${THEME_COLOR:-#default}"/>
```

## Themes

The parser integrates with existing theme system:

1. If `get_fzf_colors` function exists, it's used automatically
2. Fallback to XML-defined colors
3. Dynamic variable expansion for theme colors

## Examples

See `examples/example_usage.sh` for complete examples:

```bash
./examples/example_usage.sh simple    # Simple menu
./examples/example_usage.sh episode   # Episode picker
./examples/example_usage.sh season    # Season picker
./examples/example_usage.sh build     # Show generated args
```

## Requirements

- `xmllint` (libxml2-utils)
- `bash` 4.0+
- `fzf`

### Installing xmllint

**macOS:**
```bash
brew install libxml2
```

**Ubuntu/Debian:**
```bash
sudo apt-get install libxml2-utils
```

**Fedora:**
```bash
sudo dnf install libxml2
```

## Limitations

1. Requires `xmllint` for XML parsing
2. Complex shell variable expansion may need escaping
3. Preview scripts with complex quotes need careful XML escaping

## Future Enhancements

- [ ] JSON/YAML alternative formats
- [ ] Layout inheritance/templates
- [ ] Visual layout editor
- [ ] Runtime theme switching
- [ ] Layout composition (nested layouts)
- [ ] Animation definitions
- [ ] Screen size awareness

## Contributing

To add a new layout:

1. Create XML file in `layouts/`
2. Follow schema in `schema/layout_schema.xml`
3. Test with `./lib/ui_parser.sh --validate your-layout`
4. Add to documentation

## License

Same as parent project.
