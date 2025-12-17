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
CACHE_TTL = 14400  # 4 hours

# Global flags
REFRESH_CACHE = False

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
    if REFRESH_CACHE:
        return None
        
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

def fetch_yts_movies(limit: int = 50, page: int = 1, sort_by: str = 'date_added', 
                     query_term: str = None, genre: str = None, min_rating: int = 0,
                     order_by: str = 'desc') -> List[Dict]:
    """
    Fetch movie list from YTS API.
    
    Args:
        limit: Number of movies per page
        page: Page number
        sort_by: Sort method ('date_added', 'download_count', 'rating', 'seeds', 'peers', 'year')
        query_term: Search query (e.g. 'Avenger', '2024')
        genre: Filter by genre
        min_rating: Minimum rating filter (0-9)
        order_by: Sort order ('desc' or 'asc')
    """
    # Map 'seeds'/'peers' to 'download_count' for YTS (closest proxy generally available on list endpoint)
    # However, 'peers' isn't a direct YTS sort option, but 'download_count' suggests popularity/activity.
    # 'year' is a valid sort option.
    yts_sort = sort_by
    if sort_by in ['seeds', 'peers']:
       yts_sort = 'download_count'
       
    # Check cache
    cache_key = get_cache_key('yts_list', f"{limit}_{page}_{yts_sort}_{query_term}_{genre}_{min_rating}_{order_by}")
    cached = get_cached(cache_key)
    if cached:
        try:
            return json.loads(cached)
        except:
            pass

    for domain in YTS_DOMAINS:
        url = f"https://{domain}/api/v2/list_movies.json?limit={limit}&page={page}&sort_by={yts_sort}&order_by={order_by}"
        
        if query_term:
            url += f"&query_term={urllib.parse.quote_plus(str(query_term))}"
        if genre:
            url += f"&genre={urllib.parse.quote_plus(genre)}"
        if min_rating > 0:
            url += f"&minimum_rating={min_rating}"
        
        response = fetch_url(url)
        if not response:
            continue
        
        try:
            data = json.loads(response)
            if data.get('status') == 'ok':
                movies = data.get('data', {}).get('movies', [])
                set_cache(cache_key, json.dumps(movies))
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
# TPB FALLBACK (when YTS is unavailable)
# ═══════════════════════════════════════════════════════════════

def fetch_tpb_fallback_catalog(limit: int = 50, category: int = 207) -> List[str]:
    """
    Fallback: Fetch movies directly from TPB top100 (Default: HD Movies 207).
    Returns COMBINED format strings.
    """
    # 201=Movies, 207=HD Movies, 205=TV Shows, 208=HD TV Shows
    TPB_TOP100_URL = f'https://apibay.org/precompiled/data_top100_{category}.json'
    
    response = fetch_url(TPB_TOP100_URL, timeout=10)
    if not response:
        return []
    
    try:
        data = json.loads(response)
        results = []
        
        # Regex to detect TV Shows (Season/Episode patterns)
        tv_pattern = re.compile(r'(S\d{1,2}E\d{1,2}|Season\s*\d+|Complete\s*Series)', re.IGNORECASE)
        
        for item in data[:limit]:
            info_hash = item.get('info_hash', '')
            if not info_hash or info_hash == '0' * 40:
                continue
            
            name = item.get('name', 'Unknown')
            
            # Strict Content Filtering: If we are asking for Movies (201/207), 
            # reject anything looking like a TV show.
            if category in [201, 207, 209, 202] and tv_pattern.search(name):
                continue
            
            seeders = int(item.get('seeders', 0))
            size_bytes = int(item.get('size', 0))
            size_mb = size_bytes // (1024 * 1024)
            size_str = f"{size_mb}MB" if size_mb < 1024 else f"{size_mb/1024:.1f}GB"
            quality = extract_quality(name)
            magnet = f"magnet:?xt=urn:btih:{info_hash}"
            imdb = item.get('imdb', 'N/A')
            
            # Determine Genre/Category string
            cat_str = "Movies" if category in [201, 207, 209, 202] else "Shows"
            
            # Build COMBINED format line
            combined = (
                f"COMBINED|{name}|"
                f"TPB|"  # Single source
                f"{quality}|"
                f"{seeders}|"
                f"{size_str}|"
                f"{magnet}|"
                f"N/A|"  # No poster for TPB
                f"{imdb}|"
                f"{cat_str}|" # Genre
                f"1"  # torrent_count
            )
            results.append(combined)
        
        return results
    except Exception:
        return []

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
    
    # Extract Genres
    genres = movie.get('genres', [])
    genre_str = ', '.join(genres) if genres else 'Unknown'
    
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
        f"{genre_str}|"
        f"{len(all_torrents)}"
    )
    
    return combined

def fetch_multi_source_catalog(limit: int = 50, page: int = 1, parallel: bool = True, sort_by: str = 'date_added',
                               query_term: str = None, genre: str = None, min_rating: int = 0,
                               order_by: str = 'desc', category_mode: str = 'movies') -> List[str]:
    """
    Fetch movies from YTS and enrich each with TPB torrents.
    
    Args:
        limit: Movies per page
        page: Page number
        parallel: Use parallel fetching
        sort_by: Sort method ('date_added', 'download_count', 'rating', 'seeds', 'peers', 'year')
        query_term: Search query
        genre: Genre filter
        min_rating: Minimum rating filter
        order_by: Sort order ('desc' or 'asc')
        category_mode: 'movies' or 'shows'
    
    Returns list of COMBINED format strings.
    """
    # Fetch movies from YTS with sort option
    # Note: YTS is strictly movies. If category_mode is 'shows', YTS might return nothing suitable.
    # Future TODO: Integrate EZTV or similar for Shows. For now, Shows rely on TPB fallback.
    movies = []
    if category_mode == 'movies':
        movies = fetch_yts_movies(limit=limit, page=page, sort_by=sort_by, 
                                  query_term=query_term, genre=genre, min_rating=min_rating,
                                  order_by=order_by)
    
    # FALLBACK: If YTS fails or we want SHOWS, use TPB precompiled
    if not movies:
        # Determine TPB Category
        tpb_cat = 207  # Default HD Movies
        if category_mode == 'shows':
            tpb_cat = 208 # HD TV Shows
        
        return fetch_tpb_fallback_catalog(limit, category=tpb_cat)
    
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
    
    # Feature 8: Year-Based Sorting
    # YTS API results are sorted by date_added (upload date), which mixes old/new movies.
    # We sort by Year (DESC) to ensure Stremio-style "Latest = Newest Release".
    import re
    
    def extract_year_from_combined(entry):
        # Format: COMBINED|Title (YYYY)|...
        try:
            # Extract title part (2nd field)
            parts = entry.split('|')
            if len(parts) > 1:
                title_part = parts[1]
                # Regex for (YYYY)
                match = re.search(r'\((\d{4})\)', title_part)
                if match:
                    return int(match.group(1))
        except:
            pass
        return 0

    # Sort by Year DESC, keeping original sort order for same-year items
    # Python sort is stable, so secondary sort (date_added/rating) is preserved
    # Sort by Year DESC, keeping original sort order for same-year items
    # Python sort is stable, so secondary sort (date_added/rating) is preserved
    results.sort(key=extract_year_from_combined, reverse=True)
    
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
                        choices=['date_added', 'download_count', 'rating', 'seeds', 'peers', 'year'],
                        help='Sort method')
    parser.add_argument('--query', type=str, default=None, help='Search query (or Year)')
    parser.add_argument('--genre', type=str, default=None, help='Filter by genre')
    parser.add_argument('--min-rating', type=int, default=0, help='Minimum rating (0-9)')
    parser.add_argument('--order-by', type=str, default='desc', help='Sort order (desc/asc)')
    parser.add_argument('--category', type=str, default='movies', help='Category mode (movies/shows)')
    parser.add_argument('--sequential', action='store_true', help='Disable parallel fetch')
    parser.add_argument('--refresh', action='store_true', help='Force refresh cache (ignore cached data)')
    
    args = parser.parse_args()
    
    # Set global flags
    global REFRESH_CACHE
    REFRESH_CACHE = args.refresh
    
    # 2. Fetch Catalog
    catalog = fetch_multi_source_catalog(
        limit=args.limit,
        page=args.page,
        parallel=not args.sequential,
        sort_by=args.sort,
        query_term=args.query,
        genre=args.genre,
        min_rating=args.min_rating,
        order_by=args.order_by,
        category_mode=args.category
    )
    
    for line in catalog:
        print(line, flush=True)

if __name__ == '__main__':
    main()
