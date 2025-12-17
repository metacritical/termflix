# Termflix Python Migration Strategy

## Executive Summary

This document outlines a realistic, **incremental** strategy to migrate Termflix from Bash-first to Python-backed, using the existing Python scripts already wired into the runtime as a foundation.

As of **Dec 2025**, the state is:

- Bash remains the primary orchestration and UI layer:
  - `bin/termflix`, `bin/modules/*.sh` drive control flow and terminal UX.
  - Streaming, FZF integration, grid rendering, and terminal‑specific behavior are Bash-centric.
- Python already powers several key features:
  - Search backends: `bin/scripts/search_*.py` and `group_results.py` are called from `bin/modules/search.sh`.
  - Catalog fetching: `bin/scripts/fetch_multi_source_catalog.py` is called from `bin/modules/catalog/fetching.sh`.
  - Posters: `lib/termflix/scripts/get_poster.py` is the canonical poster provider, called from `bin/modules/posters.sh` and `bin/modules/ui/preview_fzf.sh`.
- A second “next‑gen” Python layer exists but is **not yet wired**:
  - `lib/termflix/scripts/api.py`, `catalog.py`, `category_loader.py`, `generic_torrent_scraper.py`, `get_metadata.py`, `poster_cache.py`, `search_extra_torrents.py`, `fetch_prowlarr.py`.

The migration strategy below updates earlier, more aggressive goals (e.g. “reduce Bash to 500–800 lines”) to focus instead on:

- Using existing Python pieces as **backends behind stable Bash interfaces**.
- Gradually routing more responsibilities through Python without breaking the ergonomics of the Bash CLI.
- Keeping Bash where it excels: process management, signal handling, and interactive terminal UIs (FZF, gum, kitty/viu/chafa).

**Current Status (December 2025)**:
- ✅ **Milestone 1**: Completed – Consolidated poster fetching, Python search/catalog scripts active
- ✅ **Milestone 2**: Completed – Feature flags (`USE_PYTHON_API`, `USE_PYTHON_CATALOG`) implemented, optional Python backends wired in
- ⏳ **Milestone 3**: Next phase – Stabilize Python backends, gradually transition defaults
- 📋 **Milestone 4**: Future work – Torrent layer extraction (conceptual)

### Key Benefits:
- **Maintainability**: Python's cleaner syntax and better error handling
- **Testability**: Easier unit testing with proper test frameworks
- **Extensibility**: Better support for new features and APIs
- **Performance**: Improved data processing and caching capabilities
- **Code Reduction**: Eliminate ~4,000+ lines of duplicate/dead code

## Current Architecture Analysis

### Existing Code Distribution (Dec 2025):
- **Main orchestration**: `bin/termflix` (~535 lines) – **KEEP IN BASH**; recently refactored for clarity.
- **Core Bash modules** (config, colors, deps, logging): ~1,400–1,800 lines.
- **UI Bash modules** (fzf catalog, previews, grid): ~1,500 lines.
- **Feature Bash modules** (torrent, catalog, posters, search): ~3,000 lines, with Python already backing parts of search/catalog/posters.

### Existing Python Infrastructure:
- **Runtime‑critical Python scripts (actively used)**:
  - `bin/scripts/search_yts.py`, `search_tpb.py`, `search_eztv.py`, `search_1337x.py`, `search_ytsrs.py`.
  - `bin/scripts/group_results.py`, `bin/scripts/fetch_multi_source_catalog.py`, `bin/scripts/google_poster.py`.
  - `lib/termflix/scripts/get_poster.py` (new canonical poster provider).
- **“Next‑gen” Python scripts (present but not yet wired)**:
  - `lib/termflix/scripts/api.py`, `catalog.py`, `category_loader.py`, `generic_torrent_scraper.py`, `get_metadata.py`, `poster_cache.py`, `search_extra_torrents.py`, `fetch_prowlarr.py`.
- **External tool integration**: Uses subprocess/CLI from Bash; Python scripts currently rely on the standard library only.

## Migration Strategy

### Phase 1: Solidify Existing Python Usage (High Priority, Short-Term)

Goal: Treat current Python scripts as **stable backends** and document their contracts so they can later be replaced by `lib/termflix/scripts/*.py` modules without breaking Bash callers.

#### 1.1 Search Backends
**Current entrypoint**: `bin/modules/search.sh`

- Already uses:
  - `bin/scripts/search_yts.py`, `search_tpb.py`, `search_eztv.py`, `search_1337x.py`, `search_ytsrs.py`.
  - `bin/scripts/group_results.py` for result grouping/deduplication.
- Actions:
  - Document the exact line formats and environment variables expected/produced by each search script.
  - Keep the existing Bash orchestrator (`search_torrent`) as the “search API” for the rest of the system.
  - Optionally, start refactoring `search_*.py` scripts to share logic (e.g., migrate toward `generic_torrent_scraper.py`) **without changing their CLI contract**.

#### 1.2 Catalog Fetcher
**Current entrypoint**: `bin/modules/catalog/fetching.sh`

- Already uses:
  - `bin/scripts/fetch_multi_source_catalog.py` as its primary Python backend.
- Actions:
  - Document the input flags and output format of `fetch_multi_source_catalog.py`.
  - Keep `bin/modules/catalog/fetching.sh` as the stable interface for catalog data (so callers do not depend on the specific Python script).
  - Optionally, adapt `fetch_multi_source_catalog.py` internally to call into `lib/termflix/scripts/catalog.py` when that module matures, but keep its CLI stable.

#### 1.3 Poster Provider
**Current entrypoints**:
- `bin/modules/posters.sh` (`enrich_missing_posters`)
- `bin/modules/ui/preview_fzf.sh`

- Already uses:
  - `lib/termflix/scripts/get_poster.py` as the canonical provider, with `bin/scripts/google_poster.py` as a fallback.
- Actions:
  - Document the CLI contract of `lib/termflix/scripts/get_poster.py` (arguments, exit codes, output).
  - Keep Bash modules as the UI/coordination layer (deciding when to call the Python script and how to merge back into catalog lines).

### Phase 2: Move Metadata & Catalog Logic into `lib/termflix/scripts` (Medium-Term)

Goal: Gradually migrate metadata and catalog responsibilities from ad‑hoc Python scripts into reusable Python modules, **behind existing Bash facades**.

#### 2.1 Metadata & API Layer
Targets:
- `bin/modules/api/omdb.sh`, `bin/modules/api/tmdb.sh`, `bin/modules/api/eztv.sh`.
- `lib/termflix/scripts/api.py`, `lib/termflix/scripts/get_metadata.py`.

Actions:
- Evolve `lib/termflix/scripts/api.py` / `TermflixAPI` into the canonical metadata client used by:
  - `lib/termflix/scripts/get_metadata.py`.
  - `lib/termflix/scripts/get_poster.py`.
- Introduce thin Bash wrappers (in `bin/modules/api/*.sh`) that:
  - Call a single Python entrypoint (e.g., `python3 lib/termflix/scripts/get_metadata.py <imdb_id>`).
  - Parse simple, stable output (e.g., JSON or `key=value` lines).
- Over time, reduce and then retire bespoke curl/jq logic in the Bash API modules once Python paths are stable and tested.

#### 2.2 Catalog Engine
Targets:
- `bin/modules/catalog/fetching.sh`, `bin/modules/catalog.sh`, `bin/modules/catalog/grid.sh`.
- `lib/termflix/scripts/catalog.py`, `lib/termflix/scripts/category_loader.py`.

Actions:
- Extend `lib/termflix/scripts/catalog.py` and `category_loader.py` so they can reproduce the current catalog behavior (latest/trending/popular/genre) with the same line format used by `display_catalog`.
- Introduce an **opt‑in** path in `bin/modules/catalog/fetching.sh`:
  - e.g., `USE_PYTHON_CATALOG=true` → call `python3 lib/termflix/scripts/catalog.py ...` instead of `fetch_multi_source_catalog.py`.
  - Maintain the same Bash function signatures (`get_latest_movies`, `get_latest_shows`, etc.) so callers remain unchanged.
- Once the Python catalog path is proven stable, deprecate and eventually remove `bin/scripts/fetch_multi_source_catalog.py`.

### Phase 3: Streaming & Torrent Orchestration (Longer-Term, High-Risk)

Goal: Reduce the size and complexity of `bin/modules/torrent.sh` by moving protocol‑specific logic into Python, while keeping process control and signals in Bash.

Targets:
- `bin/modules/torrent.sh` (1,700+ lines).
- Potential future Python package: `lib/termflix/torrent/` (not yet created).

Actions (conceptual, not yet implemented):
- Define a minimal “torrent session” contract in Bash:
  - e.g., `start_torrent_session <magnet>`, `get_session_status <id>`, `stop_session <id>`.
- Implement those commands in Python (a new `lib/termflix/torrent` package) that hides:
  - Whether Transmission, webtorrent, or another client is used.
  - How progress, buffering, and peer information are fetched.
- Keep:
  - Player selection, signal handling, and TTY behavior in Bash (`bin/modules/streaming/*`).

This phase is largely conceptual until earlier Python modules (catalog, API) are solid and well‑tested.

### Phase 4: UI & Interaction Enhancements (Optional, Low Priority)

Goal: Keep most terminal/UI behavior in Bash, but allow Python to prepare richer data/metadata for FZF and previews.

Targets:
- `bin/modules/ui/fzf_catalog.sh`, `bin/modules/ui/preview_fzf.sh`, `bin/modules/catalog/grid.sh`.
- `lib/termflix/scripts/poster_cache.py`, `lib/termflix/scripts/api.py`, `lib/termflix/scripts/catalog.py`.

Actions:
- Use Python to generate richer “display lines” for FZF:
  - E.g., a Python script that outputs preformatted `label|metadata|pipe_format` rows for `show_fzf_catalog`.
- Optionally wire `poster_cache.py` behind Bash:
  - Keep `bin/modules/posters.sh` as the interface, but let it call into `poster_cache.py` for pre-render decisions when configured.
- Do **not** attempt to move FZF invocation or low‑level TTY control to Python; Bash remains the right place for that.

## Proposed Directory Structure (Conceptual)

```
bin/
├── termflix                 # Main orchestration script (bash, ~300 lines)
└── modules/
    └── ui/
        └── fzf_wrapper.sh   # Minimal FZF integration (bash, ~100 lines)

lib/termflix/
├── __init__.py
├── main.py                  # Python entry point
├── config/
│   ├── __init__.py
│   ├── settings.py          # Configuration management
│   └── defaults.py          # Default values
├── api/
│   ├── __init__.py
│   ├── base.py              # Base API client
│   ├── tmdb.py              # TMDB client
│   ├── omdb.py              # OMDB client
│   └── eztv.py              # EZTV scraper
├── catalog/
│   ├── __init__.py
│   ├── manager.py           # Catalog management
│   ├── fetcher.py           # Data fetching
│   └── cache.py             # Local caching
├── ui/
│   ├── __init__.py
│   ├── themes.py            # Color/theme management
│   ├── display.py           # Terminal display helpers
│   └── fzf.py               # FZF data preparation
├── torrent/
│   ├── __init__.py
│   ├── client.py            # Torrent client abstraction
│   ├── stream.py            # Streaming logic
│   └── monitor.py           # Progress monitoring
├── poster/
│   ├── __init__.py
│   ├── cache.py             # Poster caching
│   └── fetch.py             # Poster downloading
└── utils/
    ├── __init__.py
    ├── logging.py           # Logging utilities
    ├── deps.py              # Dependency checking
    └── helpers.py           # General utilities
```

## Implementation Details

### Bash Orchestration Layer (Keep)

The main `bin/termflix` script will be simplified to:
```bash
#!/usr/bin/env bash
# 1. Environment setup and path resolution
# 2. Dependency checking
# 3. Python module invocation
# 4. FZF menu handling
# 5. Process management and cleanup
# 6. Signal handling and traps
```

### Python API Design (Future Direction)

The earlier idea of a monolithic `lib/termflix/main.py` handling CLI parsing is **not currently in place** and is not required for the next steps. For now:

- `bin/termflix` remains the only entrypoint users call.
- Python continues to be invoked from Bash as helper/backends.
- If a dedicated Python CLI is introduced later, it should:
  - Mirror the behavior of the existing Bash commands.
  - Stay compatible with `TERMFLIX_REVIEW.md` and this migration plan.

### Dependency Management

#### External Tools (Keep Subprocess Calls):
- **mpv/vlc**: Media playback (no Python replacement needed)
- **webtorrent**: Torrent streaming (no good pure-Python alternative)
- **fzf**: Fuzzy finder (best-in-class, keep)
- **kitten**: Kitty image display (terminal-specific)
- **viu/chafa**: Image display in terminal

#### Python Dependencies to Add:
```python
# requirements.txt
aiohttp>=3.8.0          # Async HTTP requests
pydantic>=1.10.0        # Data validation
click>=8.0.0            # CLI framework
rich>=12.0.0            # Terminal formatting (optional)
Pillow>=9.0.0           # Image processing
aiofiles>=0.8.0         # Async file operations
```

## Migration Timeline

### Suggested Milestones (Adjusted to Current State)

**Milestone 1 – Done / In Progress**
- ✅ Consolidate poster fetching to `lib/termflix/scripts/get_poster.py`.
- ✅ Use Python search scripts and `group_results.py` from `bin/modules/search.sh`.
- ✅ Use `fetch_multi_source_catalog.py` as central catalog fetcher from Bash.
- ✅ Remove dead Ruby code and unused duplicates (see `TERMFLIX_REVIEW.md` Part 3).

**Milestone 2 – Short Term** ✅ **COMPLETED (December 2025)**
- [x] Document and stabilize CLI contracts for:
  - `search_*.py`, `group_results.py`, `fetch_multi_source_catalog.py`, `get_poster.py`.
- [x] Introduce opt‑in flags/env vars for trying `lib/termflix/scripts/catalog.py` and `api.py` while keeping fallbacks.
  - **Status**: Implemented feature flags `USE_PYTHON_API` and `USE_PYTHON_CATALOG` in `bin/modules/core/config.sh` (Dec 2025).
  - **Wiring**: `bin/modules/api/omdb.sh` now routes to `lib/termflix/scripts/api.py` when `USE_PYTHON_API=true`.
  - **Wiring**: `bin/modules/catalog/fetching.sh` (all functions: latest, trending, popular, genre, shows) now routes to `lib/termflix/scripts/catalog.py` when `USE_PYTHON_CATALOG=true`.
  - **Default behavior**: Feature flags default to `false`, preserving existing Bash + `fetch_multi_source_catalog.py` runtime path.

**Milestone 3 – Medium Term** ✅ **COMPLETED (December 2025)**
- [x] **Made Python backends the recommended and default path**
- [x] **Python catalog and API now default**: `USE_PYTHON_CATALOG=true` and `USE_PYTHON_API=true` in `bin/modules/core/config.sh`
- [x] **Graceful fallback implemented**: Legacy Bash implementations remain as fallback
- [x] **Testing completed**: catalog.py and api.py tested for latest/trending/popular/shows/metadata
- [x] **Format compatibility verified**: Output matches legacy Bash implementations exactly
- [x] **Caching implemented**: 1 hour TTL for catalog, 7 days for API metadata
- [x] **No external dependencies**: Uses Python stdlib only
- [x] **User override available**: Via config file or environment Variables

**Migration Path for Users**:
Users can revert to legacy Bash backends anytime:
1. Config file: Add `USE_PYTHON_CATALOG=false` to `~/.config/termflix/config`
2. Environment: `export USE_PYTHON_CATALOG=false`
3. Per-command: `USE_PYTHON_CATALOG=false termflix latest`

**Milestone 4 – Long Term** (Future work, depends on Milestone 3 completion)
- [ ] **Torrent/streaming layer**: Incrementally extract torrent/protocol‑specific logic from `bin/modules/torrent.sh` into a Python package.
  - Define minimal "torrent session" contract in Bash
  - Implement Python backend for session management
  - Keep player selection, signal handling, and TTY behavior in Bash
- [ ] **Optional Python CLI**: Introduce a dedicated Python CLI entrypoint that mirrors existing Bash behavior for advanced users.
  - Must maintain 100% compatibility with current command-line interface
  - Bash wrapper remains primary entry point for most users

**Note**: Milestone 4 is conceptual and low priority. Focus remains on stabilizing Milestone 2/3 work first.

## Risk Mitigation

### Technical Risks:
1. **Subprocess Overhead**: Minimize bash↔python calls
   - Solution: Batch operations, use JSON for data transfer

2. **Terminal Compatibility**: Some features require Bash
   - Solution: Keep terminal-specific code in Bash

3. **Performance**: Python might be slower for some operations
   - Solution: Profile and optimize critical paths

### Migration Risks:
1. **Breaking Changes**: During gradual migration
   - Solution: Feature flags, maintain backward compatibility

2. **Testing**: Ensuring parity with Bash version
   - Solution: Comprehensive test suite, A/B testing

## Success Metrics

1. **Code Reduction**: Target 80% reduction in Bash code
2. **Performance**: Faster catalog loading and search
3. **Maintainability**:
   - 90%+ test coverage for Python code
   - Type hints for all public APIs
   - Documentation coverage
4. **User Experience**:
   - No regressions in functionality
   - Improved startup time
   - Better error messages

## Conclusion

Migrating Termflix to Python while keeping a minimal Bash orchestration layer will significantly improve code maintainability, testability, and extensibility. The proposed phased approach minimizes risk while delivering immediate benefits.

The key insight is that Bash should only handle what it does best:
- Terminal interaction (FZF, keyboard shortcuts)
- Process management and signal handling
- Integration with external CLI tools

Everything else - data processing, API interactions, business logic - should move to Python for better maintainability and performance.
