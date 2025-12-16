#!/usr/bin/env python3
"""
Termflix - Multi-Source Catalog Fetcher
Fetches movies from YTS and enriches with TPB torrents for more seeder options.

Usage:
    python3 fetch_multi_source_catalog.py [--limit N] [--page N]

Output:
    COMBINED format: COMBINED|Title|Sources|Qualities|Seeds|Sizes|Magnets|Poster|IMDB|Count
"""

import sys
import os
import json
import urllib.request
import urllib.parse
import ssl
import time
import hashlib
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Dict, List, Optional, Tuple

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

# YTS API domains (in order of preference)
YTS_DOMAINS = ['yts.lt', 'yts.do', 'yts.mx']

# TPB API
TPB_SEARCH_URL = 'https://apibay.org/q.php'

# Request settings
TIMEOUT = 8
MAX_RETRIES = 2

# Cache settings
CACHE_DIR = Path.home() / '.cache' / 'termflix' / 'multi_source'
CACHE_TTL = 1800  # 30 minutes

# Headers
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    'Accept': 'application/json'
}

# ═══════════════════════════════════════════════════════════════
# SSL AND HTTP UTILITIES
# ═══════════════════════════════════════════════════════════════

def create_ssl_context():
    """Create SSL context that ignores cert errors."""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx

def fetch_url(url: str, timeout: int = TIMEOUT) -> Optional[str]:
    """Fetch URL with retries."""
    for attempt in range(MAX_RETRIES):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            ctx = create_ssl_context()
            with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
                return resp.read().decode('utf-8')
        except Exception:
            if attempt < MAX_RETRIES - 1:
                time.sleep(0.5 * (attempt + 1))
            continue
    return None

# ═══════════════════════════════════════════════════════════════
# CACHE UTILITIES
# ═══════════════════════════════════════════════════════════════

def get_cache_key(prefix: str, query: str) -> str:
    """Generate cache key."""
    return hashlib.md5(f"{prefix}:{query}".encode()).hexdigest()[:16]

def get_cached(key: str) -> Optional[str]:
    """Get cached result if valid."""
    cache_file = CACHE_DIR / f"{key}.json"
    if cache_file.exists():
        try:
            mtime = cache_file.stat().st_mtime
            if time.time() - mtime < CACHE_TTL:
                return cache_file.read_text()
        except:
            pass
    return None

def set_cache(key: str, data: str):
    """Save to cache."""
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        cache_file = CACHE_DIR / f"{key}.json"
        cache_file.write_text(data)
    except:
        pass

# ═══════════════════════════════════════════════════════════════
# YTS API
# ═══════════════════════════════════════════════════════════════

def fetch_yts_movies(limit: int = 50, page: int = 1, sort_by: str = 'date_added') -> List[Dict]:
    """
    Fetch movie list from YTS API.
    
    Args:
        limit: Number of movies per page
        page: Page number
        sort_by: Sort method ('date_added', 'download_count', 'rating')
    """
    for domain in YTS_DOMAINS:
        url = f"https://{domain}/api/v2/list_movies.json?limit={limit}&page={page}&sort_by={sort_by}&order_by=desc"
        
        response = fetch_url(url)
        if not response:
            continue
        
        try:
            data = json.loads(response)
            if data.get('status') == 'ok':
                movies = data.get('data', {}).get('movies', [])
                return movies
        except:
            continue
    
    return []

def search_yts(query: str) -> List[Dict]:
    """Search YTS for additional torrents."""
    cache_key = get_cache_key('yts_search', query)
    cached = get_cached(cache_key)
    if cached:
        try:
            return json.loads(cached)
        except:
            pass
    
    encoded_query = urllib.parse.quote_plus(query)
    
    for domain in YTS_DOMAINS:
        url = f"https://{domain}/api/v2/list_movies.json?query_term={encoded_query}&limit=10"
        response = fetch_url(url, timeout=5)
        if not response:
            continue
        
        try:
            data = json.loads(response)
            if data.get('status') == 'ok':
                movies = data.get('data', {}).get('movies', [])
                torrents = []
                for movie in movies:
                    for t in movie.get('torrents', []):
                        if not t.get('hash'):
                            continue
                        torrents.append({
                            'source': 'YTS',
                            'hash': t['hash'].lower(),
                            'quality': t.get('quality', 'Unknown'),
                            'size': t.get('size', 'N/A'),
                            'seeds': int(t.get('seeds', 0)),
                            'magnet': f"magnet:?xt=urn:btih:{t['hash']}"
                        })
                set_cache(cache_key, json.dumps(torrents))
                return torrents
        except:
            continue
    
    return []

def parse_yts_torrents(movie: Dict) -> List[Dict]:
    """Parse torrents from YTS movie entry."""
    torrents = []
    for t in movie.get('torrents', []):
        if not t.get('hash'):
            continue
        torrents.append({
            'source': 'YTS',
            'hash': t['hash'].lower(),
            'quality': t.get('quality', 'Unknown'),
            'size': t.get('size', 'N/A'),
            'seeds': int(t.get('seeds', 0)),
            'magnet': f"magnet:?xt=urn:btih:{t['hash']}"
        })
    return torrents

# ═══════════════════════════════════════════════════════════════
# TPB API
# ═══════════════════════════════════════════════════════════════

def search_tpb(query: str) -> List[Dict]:
    """Search TPB for torrents matching query."""
    # Check cache first
    cache_key = get_cache_key('tpb', query)
    cached = get_cached(cache_key)
    if cached:
        try:
            return json.loads(cached)
        except:
            pass
    
    # Category 207 = HD Movies
    encoded_query = urllib.parse.quote_plus(query)
    url = f"{TPB_SEARCH_URL}?q={encoded_query}&cat=207"
    
    response = fetch_url(url, timeout=5)
    if not response:
        return []
    
    try:
        data = json.loads(response)
        
        # Check for "no results" response
        if isinstance(data, list) and len(data) == 1:
            if data[0].get('name') == 'No results returned':
                return []
        
        torrents = []
        for item in data[:10]:  # Limit to top 10 results
            info_hash = item.get('info_hash', '')
            if not info_hash or info_hash == '0' * 40:
                continue
            
            seeders = int(item.get('seeders', 0))
            size_bytes = int(item.get('size', 0))
            size_mb = size_bytes // (1024 * 1024)
            
            # Determine quality from name
            name = item.get('name', '')
            quality = extract_quality(name)
            
            torrents.append({
                'source': 'TPB',
                'hash': info_hash.lower(),
                'quality': quality,
                'size': f"{size_mb}MB" if size_mb < 1024 else f"{size_mb/1024:.1f}GB",
                'seeds': seeders,
                'magnet': f"magnet:?xt=urn:btih:{info_hash}",
                'name': name
            })
        
        # Cache results
        set_cache(cache_key, json.dumps(torrents))
        return torrents
        
    except Exception:
        return []

def extract_quality(name: str) -> str:
    """Extract quality from torrent name."""
    name_lower = name.lower()
    if any(q in name_lower for q in ['2160p', '4k', 'uhd']):
        return '4K'
    if any(q in name_lower for q in ['1080p', 'fhd']):
        return '1080p'
    if '720p' in name_lower:
        return '720p'
    if '480p' in name_lower:
        return '480p'
    return 'Unknown'

# ═══════════════════════════════════════════════════════════════
# MULTI-SOURCE AGGREGATION
# ═══════════════════════════════════════════════════════════════

def aggregate_movie(movie: Dict) -> Optional[str]:
    """
    Aggregate torrents from YTS and TPB for a single movie.
    Returns COMBINED format string.
    """
    title = movie.get('title', '')
    year = movie.get('year', '')
    poster = movie.get('medium_cover_image', 'N/A')
    imdb_id = movie.get('imdb_code', '')
    rating = movie.get('rating', 0)  # Use rating instead of IMDB ID
    
    if not title:
        return None
    
    # Collect YTS torrents from this movie
    all_torrents = parse_yts_torrents(movie)
    
    # Search query for additional sources
    search_query = f"{title} {year}"
    
    # Search TPB for additional torrents
    tpb_torrents = search_tpb(search_query)
    
    # Also search YTS for more quality options
    yts_search_torrents = search_yts(search_query)
    
    # Deduplicate by hash
    seen_hashes = {t['hash'] for t in all_torrents}
    
    for t in tpb_torrents:
        if t['hash'] not in seen_hashes and t.get('source'):
            all_torrents.append(t)
            seen_hashes.add(t['hash'])
    
    for t in yts_search_torrents:
        if t['hash'] not in seen_hashes and t.get('source'):
            all_torrents.append(t)
            seen_hashes.add(t['hash'])
    
    if not all_torrents:
        return None
    
    # Filter out torrents with empty source
    all_torrents = [t for t in all_torrents if t.get('source')]
    
    if not all_torrents:
        return None
    
    # Sort by seeds (descending)
    all_torrents.sort(key=lambda x: x['seeds'], reverse=True)
    
    # Format arrays for COMBINED output - PER-TORRENT data (not unique sources!)
    # Each array must have the same length as torrents
    per_torrent_sources = [t['source'] for t in all_torrents]  # Per-torrent source
    qualities = [t['quality'] for t in all_torrents]
    seeds = [str(t['seeds']) for t in all_torrents]
    sizes = [t['size'] for t in all_torrents]
    magnets = [t['magnet'] for t in all_torrents]
    
    # Format rating for display
    rating_str = f"{rating}/10" if rating else 'N/A'
    
    # Build COMBINED line
    display_title = f"{title} ({year})"
    combined = (
        f"COMBINED|{display_title}|"
        f"{'^'.join(per_torrent_sources)}|"  # Per-torrent sources
        f"{'^'.join(qualities)}|"
        f"{'^'.join(seeds)}|"
        f"{'^'.join(sizes)}|"
        f"{'^'.join(magnets)}|"
        f"{poster}|"
        f"{rating_str}|"
        f"{len(all_torrents)}"
    )
    
    return combined

def fetch_multi_source_catalog(limit: int = 50, page: int = 1, parallel: bool = True, sort_by: str = 'date_added') -> List[str]:
    """
    Fetch movies from YTS and enrich each with TPB torrents.
    
    Args:
        limit: Movies per page
        page: Page number
        parallel: Use parallel fetching
        sort_by: Sort method ('date_added', 'download_count', 'rating')
    
    Returns list of COMBINED format strings.
    """
    # Fetch movies from YTS with sort option
    movies = fetch_yts_movies(limit=limit, page=page, sort_by=sort_by)
    
    if not movies:
        return []
    
    results = []
    
    if parallel:
        # Parallel aggregation (faster)
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = {executor.submit(aggregate_movie, m): m for m in movies}
            for future in as_completed(futures):
                try:
                    result = future.result()
                    if result:
                        results.append(result)
                except Exception:
                    pass
    else:
        # Sequential (slower but simpler)
        for movie in movies:
            result = aggregate_movie(movie)
            if result:
                results.append(result)
    
    return results

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Multi-source catalog fetcher')
    parser.add_argument('--limit', type=int, default=50, help='Movies per page')
    parser.add_argument('--page', type=int, default=1, help='Page number')
    parser.add_argument('--sort', type=str, default='date_added', 
                        choices=['date_added', 'download_count', 'rating'],
                        help='Sort method (date_added=latest, download_count=trending, rating=popular)')
    parser.add_argument('--sequential', action='store_true', help='Disable parallel fetch')
    
    args = parser.parse_args()
    
    results = fetch_multi_source_catalog(
        limit=args.limit,
        page=args.page,
        parallel=not args.sequential,
        sort_by=args.sort
    )
    
    for line in results:
        print(line, flush=True)

if __name__ == '__main__':
    main()
