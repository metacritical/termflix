# Termflix 🎬 (FZF Edition)

Termflix is a terminal‑native torrent streaming client with a rich FZF UI, theming, posters, and persistent watch history.  
You can browse catalogs, inspect versions, and stream torrents directly into `mpv` or `vlc` – all from your terminal.

This repo is the modern, FZF‑driven layout of Termflix with:

- A two‑stage catalog UI (Stage 1 movie list + Stage 2 version picker)
- Theme‑aware colors
- Per‑torrent watch history with resume support and progress bars

---

## Features

- 🎥 **FZF Catalog UI**
  - Stage 1: movie/show list with poster preview on the right
  - Stage 2: per‑movie version picker (qualities, sources, sizes, seeds)
  - Snapshotting so Stage 2 can rebuild the Stage 1 list in its preview

- 🔍 **Multi‑Source Torrent Search**
  - Aggregates results from YTS, TPB, EZTV, 1337x and others
  - Grouping and de‑dupe handled in `bin/catalog` and `modules/catalog.sh`

- 🧲 **Version Picker Per Title**
  - See all available torrents for a movie: `[SRC] QUALITY – SIZE – 👥 SEEDS`
  - Stage 2 picker uses aligned, theme‑colored rows
  - Distinguishes mirrors by magnet hash, not just title text

- 📺 **Streaming to `mpv` / `vlc`**
  - Streams via `peerflix` on a dynamic local HTTP port
  - Automatically falls back to `transmission-cli` when `peerflix` fails
  - Smart buffering UI (optional splash screen + inline buffer status)

- 🖼 **Posters & Rich Metadata**
  - Posters from TMDB / OMDB (via `bin/api`)
  - Terminal image display via Kitty (`kitten icat`) or `viu`/`chafa`
  - Runtime, genre, year, rating, and plot pulled into the preview pane

- 🎧 **Subtitle Support**
  - Subtitle detection and auto‑loading via `modules/streaming/subtitle_manager.sh`

- 💾 **Watch History & Resume**
  - Per‑torrent‑hash JSON in `~/.config/termflix/watch_history.json`
  - Resume position fed back into `mpv` via `--start=…`
  - Stage 2 shows thin progress bars and a ▶ marker for watched versions

- 🎨 **Theme‑Aware UI**
  - CSS‑style themes under `themes/`, parsed by `modules/core/theme.sh`
  - All key UI colors go through `modules/core/colors.sh`
  - Source badges `[YTS] [TPB] [EZTV] [1337x]` and seed colors adjust per theme

---

## Installation

### Clone and Install

```bash
git clone <your-termflix-repo-url> termflix
cd termflix

# Optional helper if you keep install.sh
./install.sh
```

This repo is designed to be runnable in‑place as well:

```bash
cd termflix
./bin/termflix
```

### Dependencies

**Required**

- `bash` (4.0+ preferred; macOS 3.2 works with the compatibility shims in this repo)
- `jq` – JSON parsing for API responses and watch history
- `peerflix` **or** `webtorrent-cli` – HTTP torrent streaming
- `mpv` or `vlc` – media player

**Strongly Recommended**

- `transmission-cli` – robust fallback when `peerflix` can’t parse or stream a magnet
- `python3` – used for:
  - YTS/YTSRS scraping
  - TMDB/OMDB helper scripts
  - Poster hashing and precache scripts

**Optional (nicer UX)**

- `kitty` terminal – native image support via `kitten icat`
- `viu` or `chafa` – block‑mode image display for posters
- `bc` – smoother human‑readable speed output in buffer UIs

#### Example: macOS (Homebrew)

```bash
brew install jq mpv transmission-cli python3
npm install -g peerflix
# Optional
brew install viu
```

#### Example: Debian/Ubuntu

```bash
sudo apt-get update
sudo apt-get install jq mpv transmission-cli python3
npm install -g peerflix
```

---

## Configuration

### First Run

On first run, `bin/termflix` will:

1. Ask for your preferred player (`mpv` or `vlc`).
2. Create `~/.config/termflix/config` with:
   - `PLAYER=mpv|vlc`
   - Theme preference
   - Any persisted API configuration.
3. Initialize required directories under `~/.config/termflix/`:
   - `cache/`
   - `posters/`
   - `watch_later/`

### TMDB / OMDB API

For high‑quality posters and extra metadata:

1. Get a TMDB API key and read token from <https://www.themoviedb.org>.
2. (Optional) Get an OMDB API key from <http://www.omdbapi.com>.
3. Add them to `~/.config/termflix/config`:

```bash
TMDB_API_KEY=your_tmdb_key
TMDB_READ_TOKEN=your_tmdb_read_token
OMDB_API_KEY=your_omdb_key
```

### Themes

- Themes live under `themes/` as CSS files.
- `modules/core/theme.sh` + `colors.sh` parse and expose them as `THEME_*` / `C_*` variables.
- You can choose a theme via config:

```bash
THEME=default      # or another theme file name (without .css)
```

---

## Usage

### Basic Catalog

```bash
./bin/termflix           # Main TUI – Stage 1 catalog
termflix latest movies   # Shortcut: latest movies only
termflix latest shows    # Shortcut: latest shows only
termflix trending all
termflix popular all
```

### Search

```bash
termflix search "movie name"
termflix search "Superman 2025"
```

### Direct Magnet or .torrent

```bash
termflix "magnet:?xt=urn:btih:..."
termflix path/to/movie.torrent
```

---

## FZF UI: Stage 1 & Stage 2

### Stage 1 – Catalog List

Entry point: `show_fzf_catalog` in `modules/ui/fzf_catalog.sh`.

- Left side: numeric list of movies/shows:
  - `N. Title`
  - Uses the current theme for header and selector colors.
- Right side: preview pane driven by `modules/ui/preview_fzf.sh`:
  - Poster (Kitty or block‑mode).
  - Synopsis, genre, runtime, rating.
  - For COMBINED items, an “Available Versions” section:
    - `🧲[SRC] QUAL – SIZE – 👥 SEEDS seeds  – SourceName`
    - SRC colored using `get_source_color` (`C_YTS`, `C_TPB`, `C_1337X`, `C_EZTV`, …).

Key behaviors (Stage 1):

- Up/Down / `Ctrl+J/K` – navigate list.
- `Enter` – select current title:
  - If multiple sources: opens Stage 2 version picker.
  - If a single source: may stream directly or still open Stage 2 for preview, depending on flow.
- `Ctrl+L` – **force** Stage 2 even for single‑source items (never toggles preview).
- `q` / `Esc` – close Termflix.

### Stage 2 – Version Picker

Once a movie is selected:

- Right side: FZF picker listing versions:

  ```text
  ▶  🧲[YTS] 1080p   - 1.80 GB     - 👥  100 seeds ███████──── 35%
      🧲[TPB] 720p   - 897.0 MB    - 👥   17 seeds █───────────  0%
  ```

  - `▶` – shown when this magnet has any saved watch history; `0%` vs `>0%` is still encoded in the bar.
  - `[YTS] [TPB] [EZTV] [1337x]` – colored via `get_source_color` and the active theme.
  - Qualities, sizes, and seeds aligned via `printf` padding.
  - Progress bar and percent rendered by `generate_progress_bar` + `get_watch_percentage`.

- Left side: static Stage 2 preview (`preview_stage2.sh`):
  - Shows the Stage 1 movie list snapshot with the selected index highlighted.
  - Reuses the same catalog snapshot saved by Stage 1 (`termflix_stage1_fzf_display.txt`).

Key behaviors (Stage 2):

- Up/Down – choose a specific version (source + quality).
- `Enter` – stream selected magnet via `stream_torrent` → `stream_peerflix`.
- `Ctrl+H` / `Ctrl+O` – return to Stage 1 without streaming.
- `--no-select-1` is always used in FZF to prevent accidental auto‑play.

---

## Watch History & Resume

See `docs/WATCH_HISTORY.md` for a deep dive. High‑level:

### Storage

- Watch history file:

  ```text
  ~/.config/termflix/watch_history.json
  ```

- Shape:

  ```json
  {
    "d4b52cdea22a20c88a3b5e424c6f19acf3ce65a6": {
      "title": "Wildcat (2025)",
      "last_position": 33,
      "duration": 8185,
      "percentage": 0,
      "quality": "720p",
      "size": "1.4GB",
      "last_watched": "2025-12-19T17:31:16Z",
      "completed": false
    }
  }
  ```

### How Progress Is Recorded

Core logic lives in:

- `modules/torrent.sh` – `record_watch_progress` and streaming flow
- `bin/watch_history.sh` – `save_watch_progress`, `get_watch_position`, `get_watch_percentage`, `generate_progress_bar`

Flow:

1. `stream_peerflix` sets global `TERMFLIX_WATCH_*` variables (source, URL, quality, size, etc.).
2. Player starts with:
   - `--save-position-on-quit`
   - Custom input conf (`quit-watch-later` on `q`/`ESC`) to force state save.
   - `--log-file` pointing to a dedicated MPV debug log.
3. On exit (normal or via signal), `record_watch_progress` runs:
   - Extracts torrent hash from magnet (`btih` component).
   - Computes expected `watch_later` file from MD5 of stream URL.
   - **Method 1:** Try `start=` from `watch_later` file (when MPV creates it).
   - **Method 2:** If that fails, parse MPV log for the last `AV: HH:MM:SS / HH:MM:SS` line.
     - Converts both position and duration to seconds.
4. If both `position` and `duration` > 0:
   - Calls `save_watch_progress(hash, position, duration, quality, size, title)`.
   - Updates or creates the JSON entry atomically via `jq`.

### How Resume Works

- On the next run:
  - `stream_peerflix` calls `get_watch_position(hash)` when constructing `mpv` arguments.
  - If > 0, it adds `--start=${position_seconds}` to `mpv`.

### How the UI Uses It

Stage 2 version picker:

- `get_watch_percentage(hash)`:
  - Returns `""` if no entry.
  - Returns an integer (often 0…100) if there is history.
- If non‑empty:
  - `generate_progress_bar(pct)` draws a thin pink/gray line plus `%`.
  - If `pct > 0`, a `▶` is shown to the left of the source badge.

This makes it obvious which exact version you watched and approximately how far.

---

## Architecture Overview

Key entry points:

- `bin/termflix` – main CLI wrapper and orchestrator
  - Loads core UI modules, catalog, search, posters, watch_history, and torrent streaming.

Core modules:

- `modules/core/colors.sh` / `theme.sh` – theming and color variables.
- `modules/catalog.sh` + `bin/catalog` – fetching and grouping catalog data.
- `modules/search.sh` – search utilities and plumbing.
- `modules/torrent.sh` – high‑level streaming orchestration (peerflix, transmission, mpv/vlc).
- `modules/watch_history.sh` – watch history JSON helpers and progress bar.
- `modules/ui/fzf_catalog.sh` – Stage 1 catalog + Stage 2 version picker.
- `modules/ui/preview_fzf.sh` – Stage 1 right‑hand preview.
- `modules/ui/preview_stage2.sh` – Stage 2 left‑hand preview (static Stage 1 snapshot).
- `modules/streaming/*` – buffer monitor, subtitle manager, mpv transition, etc.

Docs:

- `docs/WATCH_HISTORY.md` – detailed design and rationale for the watch history subsystem.
- `VIBE_CHECK.md` – “system prompt” style guidelines and invariants for future edits.

---

## Development Notes

- This repo is heavily scripted in Bash; prefer compatibility with macOS’s Bash 3.2 when possible.
- Respect `VIBE_CHECK.md` invariants:
  - Do not change Stage 2 `Ctrl+L` semantics (always open version picker).
  - Keep `--no-select-1` on FZF pickers that control streaming.
  - Preserve catalog grouping via `bin/catalog` → `group_results.py`.
- Use `tests/ui/test_watch_history.sh` when modifying watch history code to verify behavior.

Suggested development commands:

```bash
# Run main TUI
./bin/termflix

# Quick watch_history sanity test
bash tests/ui/test_watch_history.sh
```

---

## License & Contributing

- License: MIT (see the LICENSE file if present in this repo; otherwise reuse the license terms from the original Termflix project you cloned from).
- Contributions:
  - Open issues/PRs for:
    - New themes
    - Additional torrent sources
    - Better progress/resume behaviors
    - Bugfixes in the FZF UI or watch history parsing

If you extend the UI or the watch history behavior, please also update:

- `docs/WATCH_HISTORY.md`
- This `README.md`
- Any relevant `VIBE_CHECK` invariants

to keep future “vibe coding” from accidentally regressing the work you’ve done.
