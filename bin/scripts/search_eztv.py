#!/usr/bin/env python3
"""
Termflix - EZTV TV Show Search
Searches EZTV for TV show torrents with enhanced parsing.

Features:
- Season/Episode parsing (S01E05, 1x05, etc.)
- Quality tag extraction (1080p, HDTV, WEB-DL)
- Show name normalization
- Multiple domain fallback
- Response caching
- Retry logic with exponential backoff

Input: Search query via environment variable SEARCH_QUERY or command line arg
Output: Pipe-delimited results to stdout

Format: EZTV|Title|Magnet|Quality|Seeds|Size|Season|Episode|IMDB_ID
"""
import sys
import os
import re
import json
import time
import hashlib
import urllib.parse
import urllib.request
from pathlib import Path

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

# Domain fallback list
EZTV_DOMAINS = [
    "https://eztv.re",
    "https://eztv.wf",
    "https://eztv.it",
    "https://eztv.ch",
]

# Cache settings
CACHE_DIR = Path.home() / ".cache" / "termflix" / "eztv"
CACHE_TTL = 3600  # 1 hour in seconds

# Request settings
MAX_RESULTS = 20
REQUEST_TIMEOUT = 8
MAX_RETRIES = 3
RETRY_DELAY = 1  # Base delay for exponential backoff


# ═══════════════════════════════════════════════════════════════
# PARSING FUNCTIONS
# ═══════════════════════════════════════════════════════════════

def parse_episode_info(title: str) -> dict:
    """
    Parse season/episode information from torrent title.
    
    Handles formats:
    - S01E05, s01e05, S01E05-E08
    - 1x05, 1X05
    - Season 1 Episode 5
    - S01 E05 (with space)
    
    Returns dict with: season, episode, formatted (e.g., "S01E05")
    """
    patterns = [
        r'[Ss](\d{1,2})[Ee](\d{1,3})',              # S01E05
        r'(\d{1,2})[xX](\d{1,3})',                   # 1x05
        r'[Ss]eason\s*(\d+)\s*[Ee]pisode\s*(\d+)',   # Season 1 Episode 5
        r'[Ss](\d{1,2})\s+[Ee](\d{1,3})',            # S01 E05 (with space)
    ]
    
    for pattern in patterns:
        match = re.search(pattern, title)
        if match:
            season = int(match.group(1))
            episode = int(match.group(2))
            return {
                'season': season,
                'episode': episode,
                'formatted': f"S{season:02d}E{episode:02d}"
            }
    
    # Try to detect season-only pack (e.g., "Show S01 Complete")
    season_only = re.search(r'[Ss](\d{1,2})(?:\s|\.|\-|$)', title)
    if season_only:
        season = int(season_only.group(1))
        return {
            'season': season,
            'episode': 0,  # 0 indicates full season pack
            'formatted': f"S{season:02d}"
        }
    
    return {'season': 0, 'episode': 0, 'formatted': ''}


def extract_quality(title: str) -> str:
    """
    Extract video quality from torrent title.
    Returns the highest/best quality found.
    """
    # Order matters: check higher quality first
    quality_patterns = [
        (r'2160p|4[Kk]|UHD', '2160p'),
        (r'1080p|1080i|FHD', '1080p'),
        (r'720p|HD(?!TV)', '720p'),
        (r'480p|SD', '480p'),
    ]
    
    source_patterns = [
        (r'WEB-?DL|WEBDL', 'WEB-DL'),
        (r'WEB-?Rip|WEBRip', 'WEBRip'),
        (r'HDTV', 'HDTV'),
        (r'BluRay|BDRip|BRRip|Blu-Ray', 'BluRay'),
        (r'DVDRip|DVDR', 'DVDRip'),
    ]
    
    quality = ''
    source = ''
    
    for pattern, label in quality_patterns:
        if re.search(pattern, title, re.IGNORECASE):
            quality = label
            break
    
    for pattern, label in source_patterns:
        if re.search(pattern, title, re.IGNORECASE):
            source = label
            break
    
    if quality and source:
        return f"{quality} {source}"
    elif quality:
        return quality
    elif source:
        return source
    else:
        return 'Unknown'


def extract_show_name(title: str) -> str:
    """
    Extract clean show name from torrent title.
    Strips quality tags, season/episode info, and release group names.
    """
    name = title
    
    # Remove common release group tags
    name = re.sub(r'\[.*?\]', '', name)  # [EZTV], [rartv], etc.
    name = re.sub(r'\(.*?\)', '', name)  # (2024), etc.
    
    # Remove season/episode patterns
    name = re.sub(r'[Ss]\d{1,2}[Ee]\d{1,3}.*', '', name)
    name = re.sub(r'\d{1,2}[xX]\d{1,3}.*', '', name)
    name = re.sub(r'[Ss]eason\s*\d+.*', '', name, flags=re.IGNORECASE)
    
    # Remove quality and source tags
    quality_tags = [
        '2160p', '1080p', '720p', '480p', '4K', 'UHD', 'FHD', 'HD', 'SD',
        'WEB-DL', 'WEBDL', 'WEBRip', 'HDTV', 'BluRay', 'BDRip', 'BRRip',
        'DVDRip', 'DVDR', 'x264', 'x265', 'HEVC', 'H264', 'H265', 'AAC',
        'AC3', 'DTS', 'TrueHD', 'Atmos', '10bit', 'HDR', 'DoVi',
    ]
    for tag in quality_tags:
        name = re.sub(rf'\b{tag}\b', '', name, flags=re.IGNORECASE)
    
    # Remove trailing release group (e.g., -ETTV, -LOL)
    name = re.sub(r'-[A-Za-z0-9]+$', '', name)
    
    # Normalize separators
    name = name.replace('.', ' ').replace('_', ' ')
    
    # Clean up whitespace
    name = ' '.join(name.split())
    
    return name.strip()


def extract_year(title: str) -> str:
    """Extract year from title if present."""
    match = re.search(r'\b(19\d{2}|20\d{2})\b', title)
    return match.group(1) if match else ''


# ═══════════════════════════════════════════════════════════════
# CACHING
# ═══════════════════════════════════════════════════════════════

def get_cache_path(query: str) -> Path:
    """Generate cache file path for a query."""
    query_hash = hashlib.md5(query.lower().encode()).hexdigest()
    return CACHE_DIR / f"{query_hash}.json"


def get_cached_results(query: str) -> list | None:
    """Get cached results if valid."""
    cache_path = get_cache_path(query)
    
    if not cache_path.exists():
        return None
    
    try:
        file_age = time.time() - cache_path.stat().st_mtime
        if file_age > CACHE_TTL:
            return None
        
        with open(cache_path, 'r') as f:
            return json.load(f)
    except Exception:
        return None


def save_to_cache(query: str, results: list):
    """Save results to cache."""
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        cache_path = get_cache_path(query)
        with open(cache_path, 'w') as f:
            json.dump(results, f)
    except Exception:
        pass  # Silently fail on cache errors


# ═══════════════════════════════════════════════════════════════
# API FUNCTIONS
# ═══════════════════════════════════════════════════════════════

def make_request(url: str, timeout: int = REQUEST_TIMEOUT) -> dict | None:
    """Make HTTP request with timeout."""
    try:
        req = urllib.request.Request(
            url,
            headers={
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
                'Accept': 'application/json',
            }
        )
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception:
        return None


def search_eztv_api(query: str, domain: str) -> list:
    """Search EZTV API on a specific domain."""
    encoded_query = urllib.parse.quote_plus(query)
    api_url = f"{domain}/api/get-torrents?imdb_id=&limit={MAX_RESULTS}&page=1&query_string={encoded_query}"
    
    data = make_request(api_url)
    if not data:
        return []
    
    torrents_count = data.get('torrents_count', 0)
    if torrents_count == 0:
        return []
    
    return data.get('torrents', [])


def search_eztv(query: str) -> list:
    """
    Search EZTV for TV show torrents with retry and fallback.
    Returns list of formatted result strings.
    """
    if not query:
        return []
    
    # Check cache first
    cached = get_cached_results(query)
    if cached is not None:
        return cached
    
    results = []
    torrents = []
    
    # Try each domain with retries
    for domain in EZTV_DOMAINS:
        for attempt in range(MAX_RETRIES):
            torrents = search_eztv_api(query, domain)
            if torrents:
                break
            # Exponential backoff
            if attempt < MAX_RETRIES - 1:
                time.sleep(RETRY_DELAY * (2 ** attempt))
        
        if torrents:
            break
    
    if not torrents:
        return []
    
    # Process torrents
    for torrent in torrents:
        magnet = torrent.get('magnet_url')
        if not magnet:
            continue
        
        title = torrent.get('title', 'Unknown')
        seeds = torrent.get('seeds', 0)
        size_bytes = torrent.get('size_bytes', 0)
        imdb_id = torrent.get('imdb_id', '')
        
        # Convert size to MB
        try:
            size_mb = int(size_bytes) // (1024 * 1024)
            if size_mb >= 1024:
                size_str = f"{size_mb / 1024:.1f}GB"
            else:
                size_str = f"{size_mb}MB"
        except Exception:
            size_str = "0MB"
        
        # Parse episode info
        ep_info = parse_episode_info(title)
        quality = extract_quality(title)
        show_name = extract_show_name(title)
        
        # Format IMDB ID properly (tt1234567 format)
        if imdb_id and not str(imdb_id).startswith('tt'):
            imdb_id = f"tt{imdb_id}"
        
        # Output format: EZTV|Title|Magnet|Quality|Seeds|Size|Season|Episode|IMDB_ID
        result = f"EZTV|{title}|{magnet}|{quality}|{seeds} seeds|{size_str}|{ep_info['season']}|{ep_info['episode']}|{imdb_id}"
        results.append(result)
    
    # Save to cache
    save_to_cache(query, results)
    
    return results


# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

if __name__ == '__main__':
    # Get query from environment or command line
    query = os.environ.get('SEARCH_QUERY', '')
    if not query and len(sys.argv) > 1:
        query = ' '.join(sys.argv[1:])
    
    if not query:
        sys.exit(0)
    
    # Search and output results
    results = search_eztv(query)
    for result in results:
        print(result, flush=True)
