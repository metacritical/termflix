## Direct FZF Calls (By Stage / Flow)

Notes:
- "Direct" means a script invokes `fzf` itself (even if it parses TML args).
- TML layouts exist for some, but are not fully used to run `fzf`.
- Preview scripts are not "direct" calls, but are still part of the UI surface (invoked by fzf via `--preview`).

### Stage 1: Catalog (Movies/Shows list)
- `modules/ui/catalog/fzf_catalog.sh`
  - Direct `fzf` call for the main catalog list.
  - TML (`modules/ui/layouts/main-catalog.tml`) is used to build args, but `fzf` is still invoked inline.

#### Stage 1 Preview: Shows Episode Table (not a direct call)
- `modules/ui/catalog/preview_fzf.sh`
  - Renders the "Season X Episodes" table inside the Stage 1 preview pane.
  - Uses fzf-provided `FZF_PREVIEW_COLUMNS` to size columns and keeps a fixed-width lock column so locked episodes don't shift/clobber the date column.
  - Title rendering does not truncate; note that some episode titles may already include `...` upstream (TMDB data).

### Stage 2: Movie Version Picker
- `modules/ui/catalog/fzf_catalog.sh`
  - Kitty mode: migrated to `tml_run_fzf` via `modules/ui/layouts/movie-version-picker-kitty.xml`.
  - Non-kitty mode: migrated to `tml_run_fzf` via `modules/ui/layouts/movie-version-picker.xml`.
  - Stage 2 left pane uses a static Stage 1 list snapshot from `${TMPDIR:-/tmp}/termflix_stage1_fzf_display.txt` (header snapshot rendering removed to prevent stale headers like “Harry Potter …”).

### Stage 2: Shows (Episodes / Versions / Season)
- `modules/ui/pickers/episode_picker.sh`
  - Migrated: now uses `tml_run_fzf` and preview script is in TML.
- `modules/ui/catalog/fzf_catalog.sh`
  - Episode version picker: moved to `tml_run_fzf` + preview script in TML; Ctrl+L behaves like Enter.
- `modules/ui/pickers/season_picker.sh`
  - Migrated: now uses `tml_run_fzf`.

### Stage 3: Streaming Buffer UI
- `modules/streaming/buffer_ui.sh`
  - Migrated: now uses `tml_run_fzf` via `modules/ui/layouts/buffer-ui.xml`.

## Supporting Menus (not stages, but in flow)
- `bin/termflix`
  - Type selector: migrated to `tml_run_fzf` via `modules/ui/layouts/type-selector.xml`.
  - Sort selector: migrated to `tml_run_fzf` via `modules/ui/layouts/sort-selector.xml`.
  - Genre selector: migrated to `tml_run_fzf` via `modules/ui/layouts/genre-selector.xml`.
  - Year/rating filters: direct `fzf` calls (inline).
  - Language filter: direct `fzf` call (inline).
  - Search prompt (FZF input fallback): direct `fzf` call.

## Migration Status
- Done: Stage 2 season picker (`modules/ui/pickers/season_picker.sh`), episode picker (`modules/ui/pickers/episode_picker.sh`), movie version picker, episode version picker.
- Remaining: Main catalog, supporting menus (year/rating filters, language filter, search prompt).
