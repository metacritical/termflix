## Direct FZF Calls (By Stage / Flow)

Notes:
- "Direct" means a script invokes `fzf` itself (even if it parses TML args).
- TML layouts exist for some, but are not fully used to run `fzf`.

### Stage 1: Catalog (Movies/Shows list)
- `modules/ui/catalog/fzf_catalog.sh`
  - Direct `fzf` call for the main catalog list.
  - TML (`modules/ui/layouts/main-catalog.tml`) is used to build args, but `fzf` is still invoked inline.

### Stage 2: Movie Version Picker
- `modules/ui/catalog/fzf_catalog.sh`
  - Kitty mode: migrated to `tml_run_fzf` via `modules/ui/layouts/movie-version-picker-kitty.xml`.
  - Non-kitty mode: migrated to `tml_run_fzf` via `modules/ui/layouts/movie-version-picker.xml`.

### Stage 2: Shows (Episodes / Versions / Season)
- `modules/ui/pickers/episode_picker.sh`
  - Migrated: now uses `tml_run_fzf` and preview script is in TML.
- `modules/ui/catalog/fzf_catalog.sh`
  - Episode version picker: moved to `tml_run_fzf` + preview script in TML; Ctrl+L behaves like Enter.
- `modules/ui/pickers/season_picker.sh`
  - Migrated: now uses `tml_run_fzf`.

### Stage 3: Streaming Buffer UI
- `modules/streaming/buffer_ui.sh`
  - Direct `fzf` call (no TML layout yet).

## Supporting Menus (not stages, but in flow)
- `bin/termflix`
  - Type selector, sort selector, genre selector, year/rating filters, language filter, search prompt:
    all are direct `fzf` calls (some use TML args, some are fully inline).

## Migration Status
- Done: Stage 2 season picker (`modules/ui/pickers/season_picker.sh`), episode picker (`modules/ui/pickers/episode_picker.sh`), movie version picker, episode version picker.
- Remaining: Main catalog, supporting menus, streaming buffer UI.
