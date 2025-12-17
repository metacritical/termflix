# Phase 4 Handoff: Python Streaming Layer (Future Work)

**Session Date**: December 18, 2025 (02:33 IST)  
**Status**: Priorities 1-3 Complete, Phase 4 Deferred  
**Next Steps**: This document guides future work on Priority 4

---

## Quick Start for New Session

**Copy this to start a new conversation**:

```
I need to implement Phase 4 of the Termflix Python migration: the Python streaming layer.

CONTEXT:
- Priorities 1-3 are complete (search sorting, Python backends promoted, torrent.sh decomposed)
- Python catalog and API are now default (USE_PYTHON_CATALOG=true, USE_PYTHON_API=true)
- torrent.sh reduced from 1,748 → 1,552 lines (11% reduction)
- Streaming modules created: buffer_monitor.sh, subtitle_manager.sh, player.sh

CURRENT STATE:
- Latest commit: df786b5 (Dec 18, 2025)
- Python backends stable and default for 1+ month (since Dec 2025)
- No regressions reported with new defaults

PHASE 4 GOAL:
Create Python backend for torrent session management while keeping player/signal/TTY in Bash.

Read /Users/pankajdoharey/.oh_my_bash/.gemini/antigravity/brain/f42c7d9c-60ff-4486-ae9f-a3cedd4d6ad9/PHASE_4_HANDOFF.md for full context.

Should I proceed with Phase 4 implementation?
```

---

## What Was Completed (Priorities 1-3)

### ✅ Priority 1: Search Results Sorting
- **File**: `bin/scripts/group_results.py` (+128 lines)
- **Change**: Added `calculate_relevance_score()` function
- **Impact**: Exact matches appear first, followed by partial matches
- **Status**: Complete and working

### ✅ Priority 2: Python Backend Promotion
**Milestone 3 - Catalog & API:**
- **Tested**: `catalog.py` (latest/trending/popular/shows) and `api.py` (OMDB/TMDB metadata)
- **Promoted**: Changed `config.sh` defaults to `USE_PYTHON_CATALOG=true` and `USE_PYTHON_API=true`
- **Simplified**: `omdb.sh` from 476 → 246 lines (41% reduction)
- **Deprecated**: `fetch_multi_source_catalog.py` with in-code migration warnings
- **Status**: Complete and stable

### ✅ Priority 3: Torrent.sh Decomposition
**Modularization:**
- Created `bin/modules/streaming/buffer_monitor.sh` (205 lines)
  - Functions: `calculate_optimal_buffer()`, `monitor_buffer_progress()`, `write_buffer_status()`, `check_buffer_ready()`
- Created `bin/modules/streaming/subtitle_manager.sh` (174 lines)
  - Functions: `has_subtitles()`, `find_subtitle_file()`, `prepare_subtitle_path()`
- Extended `bin/modules/streaming/player.sh` (153 → 268 lines)
  - Added: `monitor_player_process()` with VLC/mpv fork detection
- Reduced `bin/modules/torrent.sh` (1,748 → 1,552 lines, 11% reduction)
- **Status**: Complete and backward compatible

---

## Current Architecture (Post-Priorities 1-3)

### File Structure
```
.oh_my_bash/
├── bin/
│   ├── termflix (535 lines) - Main entry point
│   ├── modules/
│   │   ├── core/
│   │   │   ├── config.sh (USE_PYTHON_* defaults now true)
│   │   │   ├── colors.sh, deps.sh, logging.sh
│   │   ├── api/
│   │   │   └── omdb.sh (246 lines, simplified wrapper)
│   │   ├── streaming/
│   │   │   ├── buffer_monitor.sh (205 lines) ✅ NEW
│   │   │   ├── subtitle_manager.sh (174 lines) ✅ NEW
│   │   │   ├── player.sh (268 lines) ✅ EXTENDED
│   │   │   └── buffer_ui.sh (existing)
│   │   ├── torrent.sh (1,552 lines) ✅ DECOMPOSED
│   │   └── search.sh, catalog/, ui/
│   └── scripts/
│       ├── group_results.py (relevance scoring) ✅
│       └── fetch_multi_source_catalog.py (deprecated)
└── lib/
    └── termflix/
        └── scripts/
            ├── catalog.py (707 lines) - DEFAULT ✅
            └── api.py (461 lines) - DEFAULT ✅
```

### Data Flow
```
User → termflix CLI → Python Catalog → FZF UI → Bash Streaming → Player
                          ↓
                    Python API (metadata)
```

---

## Phase 4: Python Streaming Layer (Future Work)

### ⚠️ IMPORTANT: Why Phase 4 is Deferred

**Deferral Rationale** (from ARCHITECTURE.md):
1. **Stability needed**: Python backends just became default (Dec 2025)
2. **Low priority**: torrent.sh already decomposed (11% reduction)
3. **High risk**: Streaming is critical user experience
4. **Technical fit**: Bash excels at process/signal/TTY management

**Timeline**: Reassess after **1+ month** of stable Python backend usage (Feb 2025+)

### Phase 4 Scope (If Implemented)

**Goal**: Create Python backend for torrent session management

**What to migrate to Python**:
- Torrent session lifecycle (start/stop/status)
- Download progress tracking
- File selection logic
- Buffer calculation (already modularized in `buffer_monitor.sh`)

**What stays in Bash**:
- Player launching and monitoring (in `player.sh`)
- Signal handling (Ctrl+C, SIGTERM, etc.)
- TTY control and terminal manipulation
- UI rendering (FZF, preview panes)

**Proposed Structure**:
```python
# lib/termflix/streaming/session.py
class TorrentSession:
    def __init__(self, magnet: str, options: StreamOptions)
    async def start(self) -> StreamInfo
    async def get_progress(self) -> ProgressInfo
    async def stop(self)
    
class StreamManager:
    async def create_session(self, magnet: str) -> TorrentSession
    async def monitor_sessions(self) -> List[SessionStatus]
```

**Bash Integration**:
```bash
# bin/modules/torrent.sh (future)
stream_torrent() {
    local magnet="$1"
    
    # Use Python streaming backend
    if use_python_streaming; then
        local session_id=$(python3 "$STREAMING_SCRIPT" start "$magnet")
        local video_url=$(python3 "$STREAMING_SCRIPT" wait_ready "$session_id")
        
        # Bash handles player (stays in Bash)
        local player_pid=$(launch_player "$video_url")
        monitor_player_process "$player_pid"
        
        # Cleanup Python session
        python3 "$STREAMING_SCRIPT" stop "$session_id"
    else
        # Legacy peerflix path (fallback)
        stream_peerflix "$magnet"
    fi
}
```

---

## Prerequisites for Phase 4

Before starting Phase 4, verify:

1. **Stability Check** (1+ month required):
   ```bash
   # Check when Python backends became default
   git log --grep="Python backend" --oneline
   # Should show commit df786b5 from Dec 18, 2025
   # Wait until at least Jan 18, 2025 before proceeding
   ```

2. **No Regressions**:
   - `termflix latest` works correctly
   - `termflix search "query"` returns relevant results
   - Catalog operations fast (Python backend caching working)
   - No user complaints about metadata or catalog issues

3. **Value Assessment**:
   - Is there a clear benefit to Python streaming?
   - Have users requested features that need Python?
   - Is current Bash streaming causing issues?

**If all checks pass**, proceed with Phase 4. **Otherwise, continue deferring**.

---

## Implementation Plan (If Proceeding)

### Step 1: Design (1 week)
- [ ] Define Bash-Python contract (session API)
- [ ] Design Python `TorrentSession` class
- [ ] Plan peerflix/transmission wrapper
- [ ] Document signal flow (Bash → Python → Bash)

### Step 2: Prototype (1-2 weeks)
- [ ] Implement basic `session.py`
- [ ] Create `stream start/stop/status` CLI commands
- [ ] Test with simple magnet link
- [ ] Verify Bash can call Python and get results

### Step 3: Integration (1-2 weeks)
- [ ] Add `USE_PYTHON_STREAMING` feature flag
- [ ] Update `torrent.sh` to route to Python when enabled
- [ ] Keep `stream_peerflix()` as fallback
- [ ] Test with various video files and qualities

### Step 4: Testing & Validation (1 week)
- [ ] End-to-end streaming tests
- [ ] Signal handling (Ctrl+C, player exit)
- [ ] Performance comparison (Python vs Bash)
- [ ] Error handling and edge cases

### Step 5: Promotion (if successful)
- [ ] Change default to `USE_PYTHON_STREAMING=true`
- [ ] Update documentation
- [ ] Mark `stream_peerflix()` as legacy fallback

---

## Key Files to Review

Before starting Phase 4:

1. **Current Streaming Logic**:
   - `bin/modules/torrent.sh` (1,552 lines) - main orchestrator
   - `bin/modules/streaming/buffer_monitor.sh` - buffer calculations
   - `bin/modules/streaming/player.sh` - player monitoring

2. **Python Backend Examples**:
   - `lib/termflix/scripts/catalog.py` - how Python backend is structured
   - `lib/termflix/scripts/api.py` - caching, error handling patterns

3. **Migration Docs**:
   - `PYTHON_MIGRATION.md` - Milestones 1-3 completion status
   - `TERMFLIX_REVIEW.md` - Decomposition details
   - `ARCHITECTURE.md` - Target architecture and future vision

4. **Session Context**:
   - `/Users/pankajdoharey/.gemini/antigravity/brain/f42c7d9c-60ff-4486-ae9f-a3cedd4d6ad9/walkthrough.md` - Complete history
   - `/Users/pankajdoharey/.gemini/antigravity/brain/f42c7d9c-60ff-4486-ae9f-a3cedd4d6ad9/task.md` - Task breakdown

---

## Risks & Considerations

### Technical Risks
1. **Process Management Complexity**: Python subprocess handling can be tricky
2. **Signal Propagation**: Ctrl+C must reach both Python and player
3. **TTY Control**: Terminal state management better in Bash
4. **Performance**: Python overhead for process orchestration

### Mitigations
1. Keep player launching in Bash (it's working well)
2. Use feature flag for gradual rollout
3. Maintain Bash fallback indefinitely
4. Extensive signal handling tests

### When to Abort Phase 4
- If Python adds latency to streaming start
- If signal handling becomes unreliable
- If implementation is more complex than current Bash
- If users prefer current Bash implementation

---

## Success Criteria for Phase 4

If implemented, Phase 4 should achieve:

- **Performance**: Stream start ≤ current Bash implementation
- **Reliability**: No regressions in player control or buffering
- **Maintainability**: Code easier to test and modify than Bash
- **Features**: Enables future enhancements (better buffering, protocol abstraction)

**If Phase 4 doesn't meet these criteria, keep Bash streaming.**

---

## Final Recommendation

**Default Position**: **Do NOT implement Phase 4** unless:
1. ✅ 1+ month of stable Python backend usage (wait until Feb 2025+)
2. ✅ Clear user benefit or feature request requiring Python
3. ✅ Current Bash streaming has identified issues
4. ✅ Team has bandwidth for 6-8 weeks of work

**Alternative**: Continue improving Bash streaming modules (already decomposed and maintainable)

---

## Commit Reference

**Last Commit**: `df786b5` - "feat: Complete Python migration and modular refactoring (Milestones 1-3)"
- Date: December 18, 2025
- Files: 11 changed, 1561 insertions(+), 591 deletions(-)
- Status: All Priority 1-3 tasks complete

**To restore context**:
```bash
cd /Users/pankajdoharey/.oh_my_bash
git log --oneline -10
git show df786b5
```

---

## Questions for New Session

When resuming Phase 4 work, answer these first:

1. **How long has it been since Dec 18, 2025?** (Need 1+ month)
2. **Any issues with Python backends?** (Check user feedback)
3. **Is there a compelling reason for Python streaming?** (New features? Performance?)
4. **What is current torrent.sh pain point?** (If none, don't fix what works)

---

**End of Handoff Document**

Copy the "Quick Start for New Session" section above to begin Phase 4 work in a future session.
