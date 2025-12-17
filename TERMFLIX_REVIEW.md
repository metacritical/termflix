# Termflix Code Review and Refactor Notes

This document captures a snapshot of the current Termflix codebase, focusing on:

- Large/complex files that are likely refactor candidates.
- Unused, duplicate, or overlapping functionality.
- Modules that are being actively replaced by newer Python backends.
- Prime refactor targets with SOLID‑style guidance (adapted for Bash/Python).

---

## Part 1 – Unused / Duplicate / Redundant Code and Large Files

### Large or Complex Files (> ~300 LOC)

These files are long and/or mix many responsibilities, and are good candidates for modularization:

- `bin/modules/catalog/grid.sh` (~989 lines) – grid rendering, poster downloading, image rendering (kitty/viu), text layout, rating/genre lookup, cursor management.
- `bin/modules/ui/gum_catalog.sh` (~931 lines) – gum‑based catalog UI, pagination, caching, grouping, and event handling.
- `lib/termflix/scripts/catalog.py` (~706 lines) – Python catalog engine (YTS/TPB/EZTV, caching, genre handling, enrichment, CLI).
- `bin/scripts/search_yts.py` (~651 lines) – YTS search client with config, caching, retry, logging.
- `bin/scripts/fetch_multi_source_catalog.py` (~583 lines) – multi‑source catalog fetcher combining YTS + TPB with caching and aggregation.
- `bin/termflix` (~569 lines) – main CLI entrypoint that wires modules, config, and flows.
- `bin/modules/ui/fzf_catalog.sh` (~522 lines) – FZF catalog UI, navigation, staging files, preview wiring.
- `lib/termflix/scripts/api.py` (~460 lines) – unified Python metadata API (OMDB/TMDB/YTS) with caching; intended to replace shell OMDB/TMDB logic.
- `bin/modules/api/omdb.sh` (~459 lines) – OMDB API client and parsing helpers (being superseded by `lib/termflix/scripts/api.py`).
- `bin/modules/api/tmdb.sh` (~442 lines) – TMDB API client and parsing helpers (also being superseded by `lib/termflix/scripts/api.py`).
- `bin/modules/ui/preview_fzf.sh` (~413 lines) – rich preview UI (posters, metadata, descriptions).
- `lib/termflix/scripts/poster_cache.py` (~410 lines) – Python poster cache/viu pre‑renderer.
- `bin/scripts/group_results.py` (~399 lines) – torrent result grouping/deduplication into `COMBINED` lines.
- `bin/modules/core/config.sh` (~379 lines) – config discovery, parsing, and caching.
- `bin/scripts/search_eztv.py` (~350 lines) – EZTV search with caching and heuristics.
- `bin/modules/api/eztv.sh` (~343 lines) – Bash EZTV API integration.
- `bin/modules/streaming/buffer_ui.sh` (~315 lines) – buffer status UI for streaming.

These are not necessarily “bad,” but they’re the primary hot‑spots for complexity and duplication.

### 1. Poster / Metadata APIs – Bash Stack vs New Python API Module

Files:

- Legacy/primary runtime:
  - `bin/modules/posters.sh`
  - `bin/modules/ui/preview_fzf.sh`
  - `bin/modules/api/omdb.sh`
  - `bin/modules/api/tmdb.sh`
  - `bin/scripts/get_poster.py`
  - `bin/scripts/google_poster.py`
- New Python API backend:
  - `lib/termflix/scripts/api.py`
  - `lib/termflix/scripts/get_metadata.py`
  - `lib/termflix/scripts/get_poster.py`

Observations:

- The runtime path for Termflix still uses the older Bash + script pipeline:
  - `bin/termflix` sets `TERMFLIX_SCRIPTS_DIR="$SCRIPT_DIR/scripts"` and exports it.
  - `bin/modules/posters.sh` and `bin/modules/ui/preview_fzf.sh` use:
    - `"$TERMFLIX_SCRIPTS_DIR/get_poster.py"` (i.e., `bin/scripts/get_poster.py`).
    - `"$TERMFLIX_SCRIPTS_DIR/google_poster.py"`.
  - `preview_fzf.sh` gets detailed metadata via `bin/modules/api/omdb.sh` (and implicitly TMDB via the shell modules).
- Meanwhile, in `lib/termflix/scripts`:
  - `api.py` defines `TermflixAPI`, a unified Python wrapper for OMDB, TMDB, YTS with file caching, exposed as both module and CLI (search/poster/description).
  - `get_metadata.py` provides a separate metadata‑only pipeline that normalizes OMDB/TMDB/YTS/Google into an OMDB‑like shape.
  - `get_poster.py` (in `lib/termflix/scripts/`) is an optimized poster fetcher (parallel calls, better parsing).
- None of these new Python API helpers are currently referenced from `bin/termflix` or its modules.

Conclusion:

- There are two overlapping stacks for metadata/posters:
  - The current runtime uses Bash `omdb.sh`/`tmdb.sh` + `bin/scripts/get_poster.py`.
  - A richer Python metadata API (`lib/termflix/scripts/api.py` + `get_metadata.py` + `lib/.../get_poster.py`) exists but is not yet wired into the Termflix CLI.

Recommendation:

- Decide which layer should be canonical:
  - If you want to consolidate logic in Python:
    - Add lightweight Bash wrappers that call `api.py` for `movie_info`, `poster`, and `description`.
    - Gradually remove or slim down `omdb.sh`, `tmdb.sh`, `bin/scripts/get_poster.py`, and metadata logic in `preview_fzf.sh`.
  - If you prefer to keep metadata in Bash:
    - Explicitly mark `lib/termflix/scripts/api.py`, `get_metadata.py`, and `lib/.../get_poster.py` as experimental or future replacements so contributors understand the split.

### 2. Catalog Fetching – Bash Stack vs Python Catalog Engine

Files:

- `bin/modules/catalog/fetching.sh`
- `bin/scripts/fetch_multi_source_catalog.py`
- `bin/modules/catalog.sh`
- `lib/termflix/scripts/catalog.py`

Observations:

- The current runtime path:
  - Bash functions in `bin/modules/catalog/fetching.sh` expose:
    - `get_latest_movies`, `get_trending_movies`, `get_popular_movies`,
      `get_catalog_by_genre`, `get_latest_shows`, `get_new_48h_movies`.
  - These functions call `bin/scripts/fetch_multi_source_catalog.py` (YTS+TPB combination) when possible; otherwise they fall back to curl/jq against YTS/EZTV/TPB.
  - `bin/termflix` uses `bin/modules/catalog.sh`, which imports `fetching.sh`, so this Bash+Python script stack remains the active backend.
- The Python catalog engine:
  - `lib/termflix/scripts/catalog.py` defines `CatalogFetcher` with rich logic:
    - YTS, TPB, EZTV integration and caching under `~/.cache/termflix`.
    - Genre mapping and various catalog operations (latest, trending, popular, genre, shows, search, enriched catalogs).
  - `lib/termflix/scripts/category_loader.py` is a companion script that:
    - Uses `CatalogFetcher` to fetch category‑specific lists.
    - Outputs FZF‑compatible lines (`display|idx|pipe_format`).
  - These are currently self‑contained; there are no references from the Bash modules to `category_loader.py` or the `CatalogFetcher` CLI.

Conclusion:

- There are effectively **two catalog engines**:
  - The legacy Bash + `fetch_multi_source_catalog.py` path (actively used).
  - The newer Python `CatalogFetcher` engine + `category_loader.py` (not yet wired into Termflix runtime).

Recommendation:

- Decide on a single catalog backend:
  - Option A – migrate to `CatalogFetcher`:
    - Create a small wrapper script or Bash function that calls `python3 catalog.py` and standardize all catalog commands on that.
    - Remove or deprecate `fetch_multi_source_catalog.py` and related Bash logic once migration is stable.
  - Option B – keep the existing Bash stack:
    - Treat `lib/termflix/scripts/catalog.py` as experimental and mark it as such in comments.
    - Consider removing it if it is not part of the planned architecture.

### 3. Search Clients vs Generic Torrent Scraper

Files:

- Site‑specific search scripts:
  - `bin/scripts/search_yts.py`
  - `bin/scripts/search_eztv.py`
  - `bin/scripts/search_tpb.py`
  - `bin/scripts/search_1337x.py`
  - `bin/scripts/search_ytsrs.py`
- Search wiring:
  - `bin/modules/search.sh`
- Generic scraper:
  - `lib/termflix/scripts/generic_torrent_scraper.py`

Observations:

- `bin/modules/search.sh` wires Termflix search to the per‑site Python scripts and handles aggregation and grouping.
- `lib/termflix/scripts/generic_torrent_scraper.py` is an abstraction intended to implement a site scraper from a config (selectors, patterns, parsing helpers).
- There are still no references to `generic_torrent_scraper.py` in the Termflix runtime path; all live search traffic continues to go through the custom scripts.

Conclusion:

- `generic_torrent_scraper.py` overlaps in responsibility with the per‑site scripts but remains unused in production flows.

Recommendation:

- Either refactor `search_*.py` scripts to use `GenericTorrentScraper` (so they share parsing and HTTP logic), or
- Mark `generic_torrent_scraper.py` as unused/experimental and remove it if it’s not on the roadmap.

### 4. Poster Caching – Bash vs Python

Files:

- Bash cache:
  - `bin/modules/posters.sh`
- Python cache:
  - `lib/termflix/scripts/poster_cache.py`

Observations:

- `bin/modules/posters.sh` implements:
  - Cache directory discovery (`~/.config/termflix/cache/viu_renders`).
  - Cache key generation (`viu_cache_key`).
  - Existence checks, pre‑rendering via `viu`, `display_cached_viu`, batch pre‑render, and cleanup.
- `lib/termflix/scripts/poster_cache.py` implements a `PosterCache` class and related CLI that provide similar functionality from Python.
- The Bash UI code (`grid.sh`, `posters.sh`, `preview_*`) currently uses the Bash cache functions; there is still no runtime use of `poster_cache.py` inside `bin/termflix` flows.

Conclusion:

- There are two implementations of the same caching concept, one in Bash and one in Python; the Python one looks like a reusable backend but has not yet been integrated.

Recommendation:

- If the UI layer is intended to remain Bash‑centric, keep `posters.sh` as the source of truth and remove or de‑prioritize `poster_cache.py`.
- If you move more logic into Python (e.g., a Python TUI), prefer the Python cache and turn the Bash cache into a thin wrapper or retire it.

### 5. Result Grouping / Deduplication – Double Work

Files:

- `bin/scripts/group_results.py`
- `bin/modules/search.sh`

Observations:

- `group_results.py`:
  - Consumes raw lines from different search sources.
  - Normalizes titles (stripping tags, qualities, years, groups).
  - Pulls out year, quality, seeds, IMDB IDs, hashes.
  - Groups entries into logical movies/shows and outputs `COMBINED|...` lines with deduped qualities and aggregated seeds.
- `bin/modules/search.sh`:
  - Uses `group_results` (Python) when available, and then:
    - Performs a second dedupe pass in Bash using a `seen_hashes` list and magnet hash extraction.

Conclusion:

- The Bash dedupe pass partially re‑creates work already done by `group_results.py`, leading to overlapping responsibilities.

Recommendation:

- Decide which component is authoritative:
  - If Python is required, rely on `group_results.py` for deduplication and simplify the Bash fallback.
  - If Python is optional, keep the Bash dedupe only for the “no Python” path and avoid double‑deduplication when the Python script runs successfully.

### 6. Likely Unused or “Next Gen” Modules

Based on `rg` searches and wiring from `bin/termflix`, the following modules still appear to have no active call sites in the current Termflix CLI flow:

- `lib/termflix/scripts/generic_torrent_scraper.py`
- `lib/termflix/scripts/catalog.py` (as a backend; not referenced from Bash entrypoints)
- `lib/termflix/scripts/category_loader.py` (not wired into FZF/gum/catalog modules yet)
- `lib/termflix/scripts/get_metadata.py`
- `lib/termflix/scripts/poster_cache.py`
- `lib/termflix/scripts/get_poster.py` (newer implementation, not wired in)
- `lib/termflix/scripts/api.py` (unified metadata API, not yet used by `bin/termflix`)

These look like “next‑gen” Python backends intended to replace portions of the Bash stack. If they are part of the roadmap, keep them but document that they are not hooked up yet; otherwise, consider pruning or consolidating.

---

## Part 2 – Prime Refactoring Candidates (SOLID Perspective)

This section highlights specific files that are particularly good refactor targets using SOLID principles. The goal is not to force object‑oriented patterns into Bash, but to apply the same ideas: single responsibility, clear interfaces, dependency inversion, etc.

### 1. `bin/modules/catalog/grid.sh`

Symptoms:

- Very large file (~1k lines).
- Handles multiple concerns simultaneously:
  - Downloading images, computing hashes, and managing temp files.
  - Terminal geometry, column calculations, cursor positioning.
  - Rendering images via Kitty or viu, including post‑processing of ANSI output.
  - Displaying text (titles, seeds, genres, ratings) and reading metadata caches.
  - Managing state for multi‑row grid rendering and returning “next row” positions.

SOLID issues:

- **Single Responsibility Principle (SRP)**:
  - Violated: Same module is responsible for layout, IO, caching, rendering, and metadata formatting.
- **Open/Closed Principle (OCP)**:
  - Any change in display format, terminal type, or poster strategy requires editing this file, making it difficult to extend without modification.
- **Interface Segregation / Dependency Inversion**:
  - Depends directly on tools like `viu`, `kitty`, `tput`, `sed`, `jq`, and file layout; there’s no small “render API” that callers can rely on.

Refactor direction:

- Introduce smaller modules/functions with narrow contracts, e.g.:
  - `grid_layout.sh` – pure layout (compute positions, text rows).
  - `image_renderer.sh` – given an image path + coordinates, draw it using Kitty/viu/placeholder.
  - `grid_text_renderer.sh` – given a catalog item, render title/quality/seed/genre in a region.
- Define simple interfaces (function signatures) so `grid.sh` becomes an orchestrator instead of a monolith.

### 2. `bin/modules/ui/gum_catalog.sh`

Symptoms:

- Large (~900+ lines) and mixes:
  - Catalog fetching (calling backend functions, grouping, caching).
  - Pagination logic, including page calculations and navigation.
  - Integration with `gum` for UI rendering.
  - Cache key generation and storage of grouped results.

SOLID issues:

- **SRP**:
  - Combines “domain” logic (what a catalog entry is) with UI orchestration and caching.
- **OCP**:
  - To change the catalog backend or grouping behavior, this file must be edited, because those details leak into the UI.
- **Dependency Inversion Principle (DIP)**:
  - UI code depends directly on concrete backends (`get_latest_movies`, `get_trending_movies`, etc.) rather than an abstract “catalog provider” interface.

Refactor direction:

- Extract responsibilities into smaller units:
  - A “catalog provider” abstraction (Bash function contract) that returns lines, independent of UI.
  - A dedicated caching layer (shared with FZF UI where possible).
  - A narrower `display_catalog_page_gum` that only concerns itself with presenting a list + selection.
- This makes it easier to later swap the backend (e.g., move from `fetch_multi_source_catalog.py` to `CatalogFetcher`) without touching the gum UI.

### 3. `bin/modules/ui/fzf_catalog.sh`

Symptoms:

- ~500+ lines, handling:
  - Formatting FZF display lines.
  - Writing snapshot files for the “stage 2” preview.
  - Constructing a very complex FZF header and keybindings.
  - Managing FZF options, theme colors, and selection/preview behavior.

SOLID issues:

- **SRP**:
  - Multiple concerns: data presentation, keybinding policy, theming, and persistent snapshot handling.
- **OCP / Liskov Substitution Principle (LSP)**:
  - FZF behavior is coded inline; extending or replacing FZF with another picker is difficult because logic is tightly coupled.

Refactor direction:

- Separate concerns:
  - `fzf_options.sh` – constructs FZF options and color arguments (reusable across other FZF uses).
  - `catalog_snapshot.sh` – writes/reads snapshot files (`termflix_stage1_fzf_display.txt`, headers).
  - `show_fzf_catalog` – only responsible for wiring catalog data into a generic FZF invocation.
- Define small functions that can be tested independently (even visually) and replaced if needed.

### 4. `bin/modules/search.sh`

Symptoms:

- Wraps multiple responsibilities:
  - Per‑site search wrappers (`search_yts`, `search_tpb`, `search_1337x`, `search_eztv`).
  - Unified aggregation (`search_all`, `search_torrent`) with temp files, process management, timeouts.
  - Grouping and deduplication, partially duplicating `group_results.py`.
  - Debug logging and user‑facing messaging.

SOLID issues:

- **SRP**:
  - Search orchestration, low‑level process management, and result normalization are interleaved.
- **OCP**:
  - Adding/removing a search provider requires touching multiple places in the same file.
- **DIP**:
  - Bash orchestrator depends on concrete scripts (`search_*.py`) instead of an abstract “search provider” interface.

Refactor direction:

- Introduce a lightweight “provider registry”:
  - A list or small mapping of provider names → function names (e.g., `SEARCH_PROVIDERS=("search_yts" "search_tpb" "search_eztv" "search_1337x")`).
  - Unified orchestration that loops over that list.
- Extract deduplication logic into its own function (`dedupe_results`) and decide if Python grouping is mandatory or optional.
- This isolates “which providers we have” from “how we orchestrate concurrent searches”.

### 5. `bin/modules/core/config.sh`

Symptoms:

- ~379 lines that handle:
  - Discovering config locations.
  - Parsing config files.
  - Caching config values in temp files.
  - Multiple helper functions for defaults, booleans, etc.

SOLID issues:

- **SRP**:
  - File discovery, parsing, caching, and value transformation are all mixed.
- **DIP**:
  - Many consumers pull config directly from here, tightly coupling them to the current config format and cache structure.

Refactor direction:

- Split into:
  - `config_paths.sh` – where configs live.
  - `config_parser.sh` – how a single config file is parsed.
  - `config_cache.sh` – how/when config values are cached.
- Expose a small, clear “config interface”, e.g. `config_get`, `config_get_bool`, so consumers don’t depend on implementation details.

### 6. `bin/scripts/search_yts.py` and Related Per‑Site Search Scripts

Symptoms:

- `search_yts.py` is a large Python module mixing:
  - Config/environment parsing and logging.
  - HTTP client, SSL context, retry logic.
  - Caching layer.
  - HTML/JSON parsing and normalization of output format.
- Other per‑site scripts (`search_eztv.py`, `search_tpb.py`, `search_1337x.py`) each implement their own versions of some of these concerns.

SOLID issues:

- **SRP**:
  - HTTP concerns, caching, and site‑specific parsing live in the same module.
- **OCP**:
  - To add new features (e.g., different sorting, filtering, or caching strategy), each script must be modified independently.
- **DIP**:
  - Each script hard‑codes HTTP + parsing instead of depending on a shared “scraper” abstraction.

Refactor direction:

- Use `lib/termflix/scripts/generic_torrent_scraper.py` as a shared engine:
  - Extract common HTTP + cache behavior into reusable components.
  - Keep each site’s specifics in small subclasses/configurations.
- This brings the Python code closer to traditional SOLID design while reducing duplication across search scripts.

### 7. `lib/termflix/scripts/catalog.py` (If Adopted as Backend)

If you decide to make `CatalogFetcher` the canonical backend:

- It already has a reasonably SOLID shape (dataclasses, small helper methods), but:
  - **SRP** could be improved by separating:
    - API clients (YTS, TPB, EZTV) into distinct modules/classes.
    - Caching logic into its own helper.
    - CLI parsing into a small entrypoint module.
- This would:
  - Allow swapping an API client or cache implementation with minimal impact.
  - Make it easier to reuse `CatalogFetcher` in other contexts (e.g., a Python TUI).

---

## Suggested Next Steps

- Decide on canonical backends (poster, catalog, metadata, search) so that unused or redundant modules can be retired.
- Start refactoring in the highest‑value, most frequently touched files:
  - `bin/modules/catalog/grid.sh`
  - `bin/modules/ui/gum_catalog.sh`
  - `bin/modules/search.sh`
- For each, target SRP first: pull out small, testable helpers (even in Bash) and define clear function‑level contracts to approximate SOLID in a shell‑based codebase.
