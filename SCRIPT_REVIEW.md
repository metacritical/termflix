# Script Review & Testing Results

## 1. `termflix_yts_scraper.py` - YTS Website Scraper

### Purpose
Scrapes YTS websites (yts.rs, yts.hn) directly instead of using unreliable API.

### Status: ⚠️ **NOT WORKING**
- **Issue**: Connection reset by peer when accessing yts.rs/yts.hn
- **Possible causes**: 
  - Sites blocking automated requests
  - Network/firewall issues
  - HTML structure changed
- **Output format**: `YTS|Title (Year)|magnet:?xt=urn:btih:{hash}|quality|size|seeds|poster`
- **Magnets**: ✅ **CLEAN** (no `&dn=` parameter)

### Fixes Applied
- Added debug mode via `YTS_SCRAPER_DEBUG=1` environment variable
- Better error handling

### Recommendation
- **Skip integration** - Current YTS API approach in termflix is already working (when API is up)
- If YTS API is consistently down, we could try improving scraper with:
  - Better headers/cookies
  - Retry logic
  - Alternative parsing methods

---

## 2. `termflix_combine.py` - Result Combiner

### Purpose
Combines and deduplicates results from multiple sources (YTS, YTSRS, TPB) by matching titles.

### Status: ✅ **WORKING**
- Successfully groups movies by normalized title
- Combines sources, seeds, qualities, and magnets
- Output format: `COMBINED|Title|sources|seeds|qualities|magnets|poster`

### Test Results
```
Input:
  YTSRS|Noah's Arc: The Movie (2025)|magnet:?xt=urn:btih:F2A...&dn=...|720p|8 seeds
  TPB|Noah's Arc: The Movie (2025)|magnet:?xt=urn:btih:F2A...|1080p|7826 seeds

Output:
  COMBINED|Noah's Arc: The Movie (2025)|YTSRS|TPB|8|7826|720p|1080p|magnet1|magnet2|poster
```

### Recommendation
- **Consider integration** - But user previously asked to "undo multi selection"
- Useful if we want to show all sources for same movie
- Would require UI changes to handle "COMBINED" source type

---

## 3. `lib/torrent/api/yts_scraper.rb` - Ruby YTS Scraper

### Purpose
Ruby version of YTS scraper (similar to Python version).

### Status: ⚠️ **NOT TESTED**
- Requires Ruby and dependencies
- Same approach as Python scraper
- Likely has same connection issues

### Recommendation
- **Skip** - Python version already exists and has same issues
- Ruby version adds no value if Python one doesn't work

---

## Sample Magnets from Current Sources

### TPB (ThePirateBay) - ✅ CLEAN
```
magnet:?xt=urn:btih:ADA06433856C8F5845FEED8B65BE0E72E1B1787A
magnet:?xt=urn:btih:89416D1C5EDDA7A050CD23DA8FE23BD2D695BB49
magnet:?xt=urn:btih:74FA03EB883C54727E555DC24782E175477F6513
```
**Status**: ✅ Works immediately with peerflix/transmission-cli

### YTSRS - ⚠️ HAS `&dn=` PARAMETER
```
magnet:?xt=urn:btih:F2A5821B8CC59102B4070D75069788C4E7AC1D21&dn=Noah%26%23039%3Bs%20Arc%3A%20The%20Movie
magnet:?xt=urn:btih:7F4DABAB91FB386A6AC7DF519697CDCEEBB166D7&dn=A%20Machu%20Picchu%20Proposal
magnet:?xt=urn:btih:D86784186AC0293A0F3B002554A25E6F9C984F79&dn=Stand%20Your%20Ground
```
**Status**: ⚠️ Causes peerflix to hang (needs cleaning - **ALREADY FIXED** in termflix)

### YTS API (when working) - ✅ CLEAN
```
magnet:?xt=urn:btih:{hash}
```
**Status**: ✅ Works when API is available

---

## Current Issues & Fixes

### ✅ FIXED: Magnet Link Cleaning
- **Problem**: YTSRS magnets have `&dn=` parameter causing peerflix to hang
- **Solution**: Added magnet cleaning in `stream_peerflix()` function
- **Result**: All magnets are now cleaned to `magnet:?xt=urn:btih:{hash}` format

### ⚠️ YTS API Reliability
- YTS API (`yts.mx/api/v2`) is often down
- Current code falls back to TPB (working well)
- Scraper alternative doesn't work due to connection issues

---

## Integration Recommendations

### Option 1: Keep Current Approach (Recommended)
- ✅ Already working
- ✅ TPB fallback is reliable
- ✅ YTSRS works (magnets now cleaned)
- ✅ No additional dependencies

### Option 2: Integrate Combine Script (If User Wants)
- Would show combined results from all sources
- Requires UI changes to handle source selection
- User previously asked to "undo multi selection"

### Option 3: Improve YTS Scraper (Future)
- Add retry logic
- Better headers/cookies
- Alternative parsing if HTML structure changes
- Only if YTS API becomes permanently unavailable

---

## Testing Commands

```bash
# Test TPB magnets (clean)
curl -s "https://apibay.org/precompiled/data_top100_207.json" | jq -r '.[0:3][] | "TPB|\(.name)|magnet:?xt=urn:btih:\(.info_hash)"'

# Test YTSRS (has &dn= - will be cleaned by termflix)
source bin/termflix && get_ytsrs_movies "" "1080p" "year" 3 1

# Test combine script
echo "YTSRS|Movie|magnet:?xt=urn:btih:ABC&dn=Movie|720p|100MB|5 seeds|poster
TPB|Movie|magnet:?xt=urn:btih:ABC|1080p|200MB|100 seeds|N/A" | python3 bin/termflix_combine.py
```

---

## Conclusion

1. **Magnet cleaning is already implemented** ✅ - YTSRS magnets will work
2. **TPB magnets are clean** ✅ - Working perfectly
3. **YTS scraper has connection issues** ⚠️ - Not recommended for integration
4. **Combine script works** ✅ - But user previously rejected multi-selection
5. **Current approach is solid** ✅ - No urgent need to integrate these scripts

**Recommendation**: Keep current implementation. Magnet cleaning fix should resolve YTSRS issues.
