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
│    fzf --header "$header" --expect "$expect" ...             │
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
| Colors | Environment vars | `tml_get_colors` (future) |

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
- Stage 1 runtime currently uses `modules/ui/layouts/main-catalog.xml` for base layout args, while `modules/ui/layouts/main-catalog.tml` is kept as a conceptual reference for rich header experiments.
