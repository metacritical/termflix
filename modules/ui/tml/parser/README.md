# TML Parser - How It Fits In

How the bash TML parser integrates with FZF-based UIs.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    .tml Layout File                          │
│    (menu-bar, bindings, colors - declarative config)        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ (Runtime - Dynamic)
┌─────────────────────────────────────────────────────────────┐
│                    tml_parser.sh                             │
│    source tml_parser.sh                                      │
│    tml_parse "main-catalog.xml"                              │
│    header=$(tml_render_header)                               │
│    expect=$(tml_get_expect_keys)                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    fzf_catalog.sh                            │
│    printf "%s" "$data" | tml_run_fzf ...                     │
└─────────────────────────────────────────────────────────────┘
```

---

## Dynamic vs Precomputed

### Dynamic (Current) ✅
```bash
source "$UI_DIR/tml/parser/tml_parser.sh"
tml_parse "$LAYOUTS_DIR/main-catalog.xml"
menu_header=$(tml_render_header)
```
- Edit XML → immediate changes
- ~10-50ms xmllint overhead

### Precomputed (Future)
```bash
# Build: ./tml_compile layout.tml > generated/ui.sh
source generated/ui.sh
menu_header=$(render_header)
```
- Zero runtime parsing
- Requires rebuild after changes

---

## Integration Points

| Component | Before | After (TML) |
|-----------|--------|-------------|
| Header | Hardcoded bash | `tml_render_header` |
| Bindings | String literal | `tml_get_expect_keys` |
| Colors | Hardcoded fzf --color | Theme loader (`modules/core/theme.sh`) + `get_fzf_colors` |
| Symbols | Hardcoded unicode | Theme strings (`THEME_STR_*`) + seasonal exports (`TERMFLIX_LOGO_ICON`) |

---

## Usage

```bash
source "modules/ui/tml/parser/tml_parser.sh"
tml_parse "modules/ui/layouts/main-catalog.xml"

printf "%s" "$data" | tml_run_fzf \
  --header "$(tml_render_header)" \
  --expect "$(tml_get_expect_keys)" \
  --preview "preview.sh {}"
```

Note:
- Stage 1 runtime uses `modules/ui/layouts/main-catalog.xml` for base layout args, and renders the Stage 1 header pills from `modules/ui/layouts/main-catalog.tml` (`menu-bar`).
