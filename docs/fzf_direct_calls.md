## Direct FZF Calls (By Stage / Flow)

Notes:
- "Direct" means a script invokes `fzf` itself (even if it parses TML args).
- TML layouts exist for some, but are not fully used to run `fzf`.
- Preview scripts are not "direct" calls, but are still part of the UI surface (invoked by fzf via `--preview`).
- Popup pickers launched from `bin/termflix` clear `FZF_DEFAULT_OPTS` before running so main-catalog preview/binds do not leak into centered modals.

### Stage 1: Catalog (Movies/Shows list)
- `modules/ui/catalog/fzf_catalog.sh`
  - Main catalog list uses `tml_run_fzf` with `modules/ui/layouts/main-catalog.xml` for base layout args, and passes preview/expect/binds as explicit fzf args.
  - `modules/ui/layouts/main-catalog.tml` is currently kept as a conceptual layout reference, but Stage 1 runtime uses the `.xml`.

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
  - Year filter: migrated to `tml_run_fzf` via `modules/ui/layouts/year-selector.xml` and `modules/ui/layouts/year-selector-initial.xml`.
  - Rating filter: migrated to `tml_run_fzf` via `modules/ui/layouts/rating-selector.xml` and `modules/ui/layouts/rating-selector-initial.xml`.
  - Language filter: migrated to `tml_run_fzf` via `modules/ui/layouts/language-selector.xml`.
  - Search prompt (FZF input fallback): migrated to `tml_run_fzf` via `modules/ui/layouts/search-input.xml` (still uses `--print-query`).
  - Language flags note (tmux/text mode): the language picker forces `LC_ALL=C.UTF-8`, `LANG=C.UTF-8`, `RUNEWIDTH_EASTASIAN=1` and runs `fzf` with `--no-hscroll --no-scrollbar` to reduce unicode-width redraw issues.

## Migration Status
- Done: Main catalog (Stage 1), season picker, episode picker, movie version picker, episode version picker, buffer UI.
