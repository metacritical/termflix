# 🧠 VIBE CHECK PROTOCOL
> "Move fast, but don't break the things that matter."

This document serves as a **System Prompt / Context File** to prevent regressions when "vibe coding" (rapid, flow-state development) with an LLM.

## 🛡️ Core Invariants (DO NOT TOUCH)
*Files or logic that are properly "vibing" and should not be modified without explicit instruction.*

- **`modules/catalog.sh`**:
    - **Grouping Logic**: Must always call `python3 .../group_results.py`.
    - **Grouping Flag**: `needs_grouping` must default to `true` (unless in specific modes).
    - **Path Resolution**: Always use `$TERMFLIX_SCRIPTS_DIR`, never hardcoded paths.

- **`modules/ui/fzf_catalog.sh`**:
    - **Ctrl+L**: Must trigger navigation (Stage 2), NOT toggle preview.
    - **Auto-Play**: Stage 2 selection via `fzf` must ALWAYS include `--no-select-1` to prevent accidental playback.

## 🚦 Vibe Safety Rules

### 1. Atomic Cleanup
**Rule:** When asked to "clean up junk" (delete files/dirs):
- **NEVER** edit logic files (`.sh`) in the same step.
- **ONLY** usage: `rm` commands or `git rm`.
- **Verify**: After cleanup, explicitly check if deleted scripts are called by remaining code.

### 2. The "Regression Test" Prompt
Before commiting complex changes, the Agent must ask itself:
> "Am I relying on a file/path I just deleted? Did I disable a feature flag to test something and forget to re-enable it?"

### 3. Feature Flags > Deletion
Instead of deleting "old" ways of doing things, wrap them:
```bash
if [[ "$USE_NEW_VIBE" == "true" ]]; then
    new_cool_logic
else
    # The rock-solid logic we know works
    old_boring_logic
fi
```

## 📝 Pre-Commit Checklist
- [ ] Did I run `bin/termflix latest` to ensure no syntax errors?
- [ ] Did I check if `ctrl-c` or `ctrl-l` bindings were overwritten?
- [ ] Did I verify external script calls (python, ruby) still point to valid files?
