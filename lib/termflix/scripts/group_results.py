#!/usr/bin/env python3
"""
Termflix - Enhanced Result Grouping & Deduplication
Groups torrent results by title/year with hash-based deduplication.

Features:
- Enhanced title normalization (handles "The" prefix, subtitles, release groups)
- Info-hash based deduplication (prevents duplicate torrents)
- Quality/size aggregation per movie
- Data hash fallback for non-magnet entries
- Proper year separation (same title, different years = different movies)

Input: Pipe-delimited torrent results from stdin
Output: COMBINED entries to stdout
"""
import sys
import re
import hashlib
import base64
from collections import defaultdict
from typing import Dict, List, Set, Optional


# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

# Quality tier ordering (lower = better)
QUALITY_ORDER = {
    '4K': 0, '2160p': 0,
    '1080p': 1,
    '720p': 2,
    '480p': 3,
    'HDTV': 4,
    'CAM': 5, 'TS': 6, 'TC': 7,
    'Unknown': 99
}

# Tags to remove during normalization
REMOVAL_TAGS = [
    # Quality
    '2160p', '1080p', '720p', '480p', '4k', 'uhd', 'fhd', 'hd', 'sd',
    # Source
    'bluray', 'blu-ray', 'bdrip', 'brrip', 'web-dl', 'webrip', 'webdl',
    'hdrip', 'dvdrip', 'hdtv', 'pdtv', 'cam', 'ts', 'tc', 'screener', 'dvdscr', 'r5', 'ppvrip',
    # Codec (including truncated variants like 'h26' from 'h264')
    'x264', 'x265', 'x26', 'hevc', 'h264', 'h265', 'h26', 'avc', '10bit', '8bit', '12bit', 'xvid', 'divx', 'av1', 'vp9',
    # Audio - ENHANCED
    'aac', 'ac3', 'dts', 'truehd', 'atmos', 'flac', 'mp3', 'ogg', 'opus', 'lpcm', 'eac3',
    'dd5', 'dd51', 'dd71', 'ddp5', 'ddp51', 'ddp',  # Dolby Digital variants
    '51', '71', '20',  # Channel configs
    # HDR
    'hdr', 'hdr10', 'hdr10plus', 'dolby', 'dovi', 'vision', 'sdr', 'dv',
    # Streaming services - ENHANCED
    'nf', 'amzn', 'dsnp', 'hmax', 'atvp', 'pcok', 'hulu', 'max', 'pmtp',
    'netflix', 'amazon', 'disney', 'apple', 'peacock',
    # Release groups - ENHANCED
    'yts', 'yify', 'rarbg', 'eztv', 'ettv', 'sparks', 'axxo', 'ethel',
    'tepes', 'yts mx', 'yts lt', 'tigole', 'qxr', 'psypher', 'f', 'joy',
    'bone', 'flux', 'ion10', 'megusta', 'playweb', 'cmrg', 'psa', 'telly', 'ntb', 'fgt', 'evo', 'geckos',
    # Edition tags
    'repack', 'proper', 'real', 'extended', 'unrated', 'directors', 'cut',
    'theatrical', 'remastered', 'imax', 'internal', 'limited', 'remux',
    'criterion', 'anniversary', 'complete', 'dc',
    'v2', 'v3', 'v4',  # Version markers
    # Languages - ENHANCED
    'english', 'hindi', 'spanish', 'french', 'german', 'italian', 'russian',
    'korean', 'chinese', 'japanese', 'arabic', 'portuguese', 'turkish',
    'en', 'eng', 'hin', 'spa', 'fre', 'ger', 'ita', 'rus', 'kor', 'chi', 'jpn',
    'dual', 'multi', 'subbed', 'dubbed', 'subs', 'hc', 'hardcoded',
    # Misc
    'ma',  # Multi-channel audio marker
    'line audio', 'mic dubbed',
]

# Roman numeral to digit mapping for sequels
ROMAN_NUMERALS = {
    'ii': '2', 'iii': '3', 'iv': '4', 'v': '5',
    'vi': '6', 'vii': '7', 'viii': '8', 'ix': '9', 'x': '10'
}


# ═══════════════════════════════════════════════════════════════
# EXTRACTION FUNCTIONS
# ═══════════════════════════════════════════════════════════════

def extract_year(name: str) -> str:
    """Extract year (1920-2029) from torrent name."""
    # Try parens first: (2024)
    match = re.search(r'\((19[2-9]\d|20[0-2]\d)\)', name)
    if match:
        return match.group(1)
    
    # Try 4 digits surrounded by non-alnum
    match = re.search(r'(?:^|[\W_])(19[2-9]\d|20[0-2]\d)(?:$|[\W_])', name)
    if match:
        return match.group(1)
    
    return ""


def extract_info_hash(magnet: str) -> str:
    """Extract info_hash from magnet link."""
    if not magnet:
        return ""
    
    # Hex hash (40 chars)
    match = re.search(r'btih:([a-fA-F0-9]{40})', magnet)
    if match:
        return match.group(1).lower()
    
    # Base32 hash (32 chars) - convert to hex
    match = re.search(r'btih:([A-Z2-7]{32})', magnet, re.IGNORECASE)
    if match:
        try:
            hash_bytes = base64.b32decode(match.group(1).upper())
            return hash_bytes.hex().lower()
        except Exception:
            pass
    
    return ""


def extract_quality(name: str) -> str:
    """Extract quality from torrent name."""
    name_lower = name.lower()
    
    # Check quality patterns (order matters)
    if any(q in name_lower for q in ['2160p', '4k', 'uhd']):
        return '4K'
    if any(q in name_lower for q in ['1080p', '1080i', 'fhd']):
        return '1080p'
    if any(q in name_lower for q in ['720p', 'hd']):
        return '720p'
    if '480p' in name_lower or 'sd' in name_lower:
        return '480p'
    if 'hdtv' in name_lower:
        return 'HDTV'
    if 'cam' in name_lower:
        return 'CAM'
    if any(q in name_lower for q in ['ts', 'telesync']):
        return 'TS'
    if any(q in name_lower for q in ['tc', 'telecine']):
        return 'TC'
    
    return 'Unknown'


def extract_seeds(text: str) -> int:
    """Extract seed count from text."""
    match = re.search(r'(\d+)', str(text))
    return int(match.group(1)) if match else 0


def extract_imdb_id(line: str) -> str:
    """Extract IMDB ID from result line if present."""
    match = re.search(r'(tt\d{7,})', line)
    return match.group(1) if match else ""


# ═══════════════════════════════════════════════════════════════
# NORMALIZATION
# ═══════════════════════════════════════════════════════════════

def normalize_title(title: str, year: str = "") -> str:
    """
    Normalize title for grouping purposes.
    Handles: "The" prefix/suffix, quality tags, release groups, Roman numerals
    Returns: Lowercase, alphanumeric-only normalized title for comparison
    """
    if not title:
        return ""
    
    t = title.strip()
    
    # 1. Handle year in parentheses first - extract and remove
    year_match = re.search(r'\(?(19[2-9]\d|20[0-2]\d)\)?', t)
    extracted_year = year_match.group(1) if year_match else year
    
    # 2. Remove everything in brackets/parens (often contains garbage)
    t = re.sub(r'\[.*?\]', '', t)
    t = re.sub(r'\(.*?\)', '', t)
    
    # 3. Remove year from title if found
    if extracted_year:
        t = re.sub(rf'\b{extracted_year}\b', '', t)
    
    # 4. Remove common hyphenated patterns first
    hyphen_patterns = [
        r'web-dl', r'web-rip', r'blu-ray', r'hdr10?', r'dts-hd',
        r'h-264', r'h-265', r'dd5-1', r'x-264', r'x-265',
    ]
    for pat in hyphen_patterns:
        t = re.sub(pat, '', t, flags=re.IGNORECASE)
    
    # 5. Convert separators to spaces
    t = re.sub(r'[._\-\+]', ' ', t)
    
    # 6. Lowercase for comparison
    t = t.lower()
    
    # 7. Handle "The " prefix and ", The" suffix
    t = re.sub(r'^the\s+', '', t)
    t = re.sub(r',\s*the\s*$', '', t)
    
    # 8. Remove ALL known tags (extended list)
    all_tags = REMOVAL_TAGS + [
        # Additional patterns often missed
        'proper', 'real', 'limited', 'extended', 'ultimate', 'repack',
        'criterion', 'uncut', 'final', 'complete', 'special', 'edition',
        'rgb', 'bone', 'en', 'eng', 'hin', 'hindi', 'tamil',
        'amzn', 'nf', 'hmax', 'dsnp', 'atvp', 'pcok', 'hulu',
    ]
    for tag in all_tags:
        t = re.sub(r'\b' + re.escape(tag) + r'\b', '', t, flags=re.IGNORECASE)
    
    # 9. Remove version patterns (v1, v2, etc.)
    t = re.sub(r'\bv\d+\b', '', t, flags=re.IGNORECASE)
    
    # 10. Remove trailing short words (likely release groups)
    t = re.sub(r'\s+[a-z]{1,5}$', '', t)
    
    # 11. Normalize Roman numerals for sequels
    for roman, digit in ROMAN_NUMERALS.items():
        t = re.sub(rf'\b{roman}\b', digit, t)
    
    # 12. Keep only alphanumeric and spaces
    t = re.sub(r'[^a-z0-9 ]', '', t)
    
    # 13. Collapse whitespace and strip
    t = re.sub(r'\s+', ' ', t).strip()
    
    return t



def compute_data_hash(name: str, size: str, source: str) -> str:
    """Compute fallback hash from metadata when magnet hash unavailable."""
    norm_name = re.sub(r'[^a-z0-9]', '', name.lower())
    data = f"{norm_name}:{size}:{source}"
    return hashlib.md5(data.encode()).hexdigest()[:16]


# ═══════════════════════════════════════════════════════════════
# OUTPUT FUNCTIONS
# ═══════════════════════════════════════════════════════════════

def get_quality_sort_key(quality: str) -> int:
    """Get sort key for quality ordering."""
    return QUALITY_ORDER.get(quality, 99)


def calculate_relevance_score(title: str, query: str) -> int:
    """
    Calculate relevance score for sorting search results.
    
    Returns:
        1000 - Exact match
        100  - Starts with query
        10   - Contains query
        0    - No match (shouldn't happen in search results)
    
    This ensures relevant results appear first instead of being scattered.
    """
    if not query:
        return 0
    
    # Normalize for comparison
    title_lower = title.lower().strip()
    query_lower = query.lower().strip()
    
    # Exact match (highest priority)
    if title_lower == query_lower:
        return 1000
    
    # Starts with query (high priority for sequels/series)
    if title_lower.startswith(query_lower):
        return 100
    
    # Contains query (medium priority)
    if query_lower in title_lower:
        # Boost score if query is near the start
        position = title_lower.find(query_lower)
        # Score: 10-50 based on position (earlier = higher)
        position_bonus = max(0, 40 - (position * 2))
        return 10 + position_bonus
    
    return 0


def print_combined(items: List[Dict], preferred_year: str = ""):
    """Print combined result for a group of items."""
    if not items:
        return
    
    if len(items) == 1:
        print(items[0]['original'])
        return
    
    # Pick best display name (prefer one with year)
    best_name = items[0]['name']
    if preferred_year:
        for item in items:
            if preferred_year in item['name']:
                best_name = item['name']
                break
    else:
        for item in items:
            if re.search(r'\d{4}', item['name']):
                best_name = item['name']
                break
    
    # Collect and dedupe data
    sources = list(dict.fromkeys(i['source'] for i in items))  # Preserve order, dedupe
    
    # Sort qualities by tier
    quality_items = [(i['quality'], i) for i in items]
    quality_items.sort(key=lambda x: get_quality_sort_key(x[0]))
    qualities = list(dict.fromkeys(q for q, _ in quality_items))
    
    # Calculate aggregates
    seeds = [str(i['seeds']) for i in items]
    total_seeds = sum(i['seeds'] for i in items)
    sizes = list(dict.fromkeys(i['size'] for i in items))  # Dedupe sizes
    magnets = [i['magnet'] for i in items]
    
    # Get best poster
    best_poster = "N/A"
    for item in items:
        if item.get('poster') and item['poster'] != "N/A":
            best_poster = item['poster']
            break
    
    # Get IMDB ID if available
    imdb_id = ""
    for item in items:
        if item.get('imdb_id'):
            imdb_id = item['imdb_id']
            break
    
    # Format output: COMBINED|Name|Sources|Qualities|Seeds|Sizes|Magnets|Poster|IMDB|Count
    combined_line = (
        f"COMBINED|{best_name}|"
        f"{'^'.join(sources)}|"
        f"{'^'.join(qualities)}|"
        f"{'^'.join(seeds)}|"
        f"{'^'.join(sizes)}|"
        f"{'^'.join(magnets)}|"
        f"{best_poster}|"
        f"{imdb_id}|"
        f"{len(items)}"
    )
    print(combined_line)


# ═══════════════════════════════════════════════════════════════
# MAIN PROCESSING
# ═══════════════════════════════════════════════════════════════

def main():
    """Main processing - read from stdin, group results, output to stdout."""
    results = []
    seen_hashes: Set[str] = set()
    
    # Get search query from command-line argument (optional)
    search_query = ""
    if len(sys.argv) > 1:
        search_query = sys.argv[1]
    
    # Read input
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line or '|' not in line:
                continue
            results.append(line)
    except Exception:
        pass
    
    # First pass: Parse and deduplicate by hash
    title_groups: Dict[str, List[Dict]] = defaultdict(list)
    
    for line in results:
        parts = line.split('|')
        if len(parts) < 6:
            continue
        
        source = parts[0]
        name = parts[1]
        magnet = parts[2]
        quality_raw = parts[3]
        size = parts[4]
        seeds_text = parts[5] if len(parts) > 5 else "0"
        poster = parts[6] if len(parts) > 6 else "N/A"
        
        # Extract hash for deduplication
        info_hash = extract_info_hash(magnet)
        if not info_hash:
            # Fallback: compute data hash
            info_hash = "data_" + compute_data_hash(name, size, source)
        
        # Skip duplicates
        if info_hash in seen_hashes:
            continue
        seen_hashes.add(info_hash)
        
        # Extract metadata
        year = extract_year(name)
        title = normalize_title(name, year)
        quality = extract_quality(name)  # Re-extract for consistency
        imdb_id = extract_imdb_id(line)
        
        if not title:
            continue
        
        item = {
            'original': line,
            'source': source,
            'name': name,
            'magnet': magnet,
            'quality': quality if quality != 'Unknown' else quality_raw.split()[0] if quality_raw else 'Unknown',
            'size': size,
            'seeds': extract_seeds(seeds_text),
            'poster': poster,
            'year': year,
            'imdb_id': imdb_id,
            'hash': info_hash
        }
        
        # Group key includes year to separate remakes
        group_key = f"{title}_{year}" if year else title
        title_groups[group_key].append(item)
    
    # Second pass: Handle year ambiguity within groups and collect for sorting
    grouped_output: List[tuple] = []  # (relevance_score, total_seeds, items, preferred_year)
    
    for group_key, items in title_groups.items():
        # Collect all non-empty years
        known_years = set(i['year'] for i in items if i['year'])
        
        if len(known_years) <= 1:
            # No year conflict - all belong to same movie
            preferred_year = list(known_years)[0] if known_years else ""
            
            # Calculate relevance score for this group
            # Use the normalized title from the first item for scoring
            group_title = items[0]['name'] if items else ""
            relevance = calculate_relevance_score(group_title, search_query)
            
            # Calculate total seeds for secondary sorting
            total_seeds = sum(i['seeds'] for i in items)
            
            grouped_output.append((relevance, total_seeds, items, preferred_year))
        else:
            # Multiple years found - split into separate movies
            by_year: Dict[str, List[Dict]] = defaultdict(list)
            for item in items:
                y = item['year'] if item['year'] else "unknown"
                by_year[y].append(item)
            
            for year_val, sub_items in by_year.items():
                pref_year = year_val if year_val != "unknown" else ""
                
                # Calculate relevance and seeds for this sub-group
                group_title = sub_items[0]['name'] if sub_items else ""
                relevance = calculate_relevance_score(group_title, search_query)
                total_seeds = sum(i['seeds'] for i in sub_items)
                
                grouped_output.append((relevance, total_seeds, sub_items, pref_year))
    
    # Sort by relevance (descending), then by seeds (descending)
    grouped_output.sort(key=lambda x: (-x[0], -x[1]))
    
    # Print sorted results
    for _, _, items, preferred_year in grouped_output:
        print_combined(items, preferred_year=preferred_year)


if __name__ == "__main__":
    main()
