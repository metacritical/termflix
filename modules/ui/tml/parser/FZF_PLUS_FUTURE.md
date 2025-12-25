# FZF++ Future Concept

Ideas for a future "FZF++" that would enable true TML-driven interactive TUIs.

---

## The Problem

FZF is a **single-run fuzzy finder**, not a stateful UI framework:
- No re-rendering without restart
- No multiple focusable areas
- No modals/popups
- No dynamic header updates

TML describes rich UIs that FZF can't fully render.

---

## FZF++ Vision

A wrapper/replacement that adds:

### 1. Stateful Mode
```bash
fzf++ --mode stateful --layout app.tml
```
- Persists state between interactions
- Re-renders without full restart
- Supports `tml_update "#element-id" "$new_content"`

### 2. Multiple Panes
```
┌─────────────────────────────────────────┐
│ Header (menu-bar)                       │
├──────────────────────┬──────────────────┤
│ Sidebar              │ Main List        │
│ (focusable)          │ (focusable)      │
├──────────────────────┴──────────────────┤
│ Status Bar                              │
└─────────────────────────────────────────┘
```
Tab between panes, each with own bindings.

### 3. Modal Dialogs
```bash
# Pop up over current view
tml_modal "#confirm-dialog"
```

### 4. Dynamic Updates
```bash
# From handler, update specific element
tml_update "#status-text" "Loading..."
tml_refresh "#item-list"
```

---

## Implementation Approaches

### A) Pure Bash (Hard)
- Use `tput` for cursor positioning
- Manual ANSI rendering
- Complex, error-prone

### B) Go Wrapper (Recommended)
- Go binary that wraps FZF or replaces it
- Uses Bubble Tea for rendering
- TML → Bubble Tea components

### C) Enhanced FZF Fork
- Fork FZF, add multi-pane support
- Significant C effort

---

## For Now

The current bash TML parser works for:
- ✅ Header generation
- ✅ Bindings extraction
- ✅ Color configuration

Full TML support requires FZF++ or the Go TML runtime.

---

## Related

See `~/Development/tml` for the Go-based TML project that can support full interactive TUIs via Bubble Tea.
