# TML Parser Comparison: V1 vs V2

## Summary

**V2 (`tml_parser.sh`)** = Current Termflix runtime parser (supports `<fzf-layout>` and `<tml>`)
**V1 (`ui_parser.sh`)** = Legacy parser (kept for older docs/tests)

---

## V1: FZF Layout Parser (Legacy)

**File:** `modules/ui/lib/ui_parser.sh` (381 lines)

### Schema: `<fzf-layout>`
```xml
<fzf-layout id="season-picker">
  <layout direction="reverse" height="70%"/>
  <border style="rounded" label="..."/>
  <header first="true">Title</header>
  <prompt pointer="➜">Select ➜</prompt>
  <colors><color name="fg" value="#fff"/></colors>
  <bindings expect="enter,esc">
    <bind key="esc" action="abort"/>
  </bindings>
</fzf-layout>
```

### Output: Complete FZF args
```
--layout reverse --height 70% --margin 15%,20% --border rounded
--header "..." --prompt "Select ➜" --pointer ➜ --color "..." --bind=esc:abort
```

### What It Supports
| Feature | Supported |
|---------|-----------|
| Layout (reverse/height/margin/padding) | ✅ |
| Preview (position/size/script) | ✅ |
| Header | ✅ |
| Border (style/label) | ✅ |
| Prompt/Pointer | ✅ |
| Colors (theme integration) | ✅ |
| Bindings (action/return-code) | ✅ |

### Usage
V1 is deprecated and is kept only for older docs/tests/debug scripts. New code should use V2 (`tml_parser.sh`) and `tml_run_fzf`.

---

## V2: TML Parser ✅ PRODUCTION

**File:** `modules/ui/tml/parser/tml_parser.sh` (400+ lines)

### Schema: `<tml>`
```xml
<tml version="1.0" theme="crush">
  <variables><var name="category" default="movies"/></variables>
  <handlers><handler id="fetch" type="bash"/></handlers>
  <layout id="app">
    <menu-bar>
      <tab-group><tab id="movies" active="true">Movies</tab></tab-group>
    </menu-bar>
    <list source="handler:fetch"/>
    <bindings><bind key="ctrl-o" return-code="101"/></bindings>
  </layout>
</tml>
```

### What It Adds (Beyond V1)
| Feature | V1 | V2 |
|---------|----|----|
| Menu-bar with tabs | ❌ | ✅ |
| Tab groups | ❌ | ✅ |
| Dropdowns | ❌ | ✅ |
| Expression eval `${var}` | ❌ | ✅ |
| Handler declarations | ❌ | ✅ |
| Variables section | ❌ | ✅ |

### What V2 CAN'T Do (FZF Limitation)
- Dynamic re-rendering
- Multiple focus areas
- Modals/popups
- State updates without restart

---

## Recommendation

| Use Case | Parser |
|----------|--------|
| Main catalog (Stage 1) | **V2** |
| Season picker, episode picker | **V2** |
| Version picker / buffer UI | **V2** |
| Rich header with tabs | **V2** |
| Legacy scripts/tests | **V1** |

---

## Files

```
modules/ui/
├── lib/
│   └── ui_parser.sh        # V1 - Legacy parser (docs/tests)
├── tml/
│   └── parser/
│       └── tml_parser.sh   # V2 - Runtime parser used by Termflix
├── layouts/
│   ├── *.xml               # V1 layouts
│   └── *.tml               # V2 layouts (experiment)
```

---

## Archive Note
Once debug/tests are migrated off V1, `modules/ui/lib/ui_parser.sh` can be removed.

V1 remains in the repo for compatibility with older docs/tests and as a reference implementation.
New work should target V2 layouts and `tml_parser.sh`.
