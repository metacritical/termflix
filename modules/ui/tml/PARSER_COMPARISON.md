# TML Parser Comparison: V1 vs V2

## Summary

**V2 (`tml_parser.sh`)** = Current Termflix runtime parser (supports `<fzf-layout>` and `<tml>`)
**V1 (`ui_parser.sh`)** = Legacy parser (kept for older docs/tests)

---

## V1: FZF Layout Parser ✅ PRODUCTION

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
```bash
source modules/ui/lib/ui_parser.sh
build_fzf_cmd "season-picker"  # Returns FZF args
run_fzf_layout "season-picker" # Runs FZF directly
```

---

## V2: TML Parser ⚠️ EXPERIMENTAL

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
│   └── ui_parser.sh        # V1 - Production FZF parser
├── tml/
│   └── parser/
│       └── tml_parser.sh   # V2 - Experimental rich components
├── layouts/
│   ├── *.xml               # V1 layouts
│   └── *.tml               # V2 layouts (experiment)
```

---

## Archive Note

V2 TML parser remains in codebase for:
1. Header generation experiments
2. Future FZF++ development
3. Reference for Go TML implementation

V1 is the **recommended parser** for all current Termflix UI work.
