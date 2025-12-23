#!/usr/bin/env python3
"""
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
import re
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

# Headers - must look like a real browser to avoid rate limiting
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Accept-Encoding': 'gzip, deflate, br',
    'Connection': 'keep-alive',
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
    """Fetch URL with retries and gzip support."""
    import gzip
    import io
    
    for attempt in range(MAX_RETRIES):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            ctx = create_ssl_context()
            with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
                data = resp.read()
                # Handle gzip encoding
                encoding = resp.headers.get('Content-Encoding', '')
                if 'gzip' in encoding:
                    data = gzip.decompress(data)
                elif 'deflate' in encoding:
                    import zlib
                    data = zlib.decompress(data)
                return data.decode('utf-8')
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

def fetch_url_curl(url: str, timeout: int = 10) -> Optional[str]:
    """Fetch URL using curl subprocess (better browser emulation)."""
    import subprocess
    try:
        result = subprocess.run(
            [
                'curl', '-sL', '--max-time', str(timeout),
                '-H', 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                '-H', 'Accept: application/json, text/plain, */*',
                '-H', 'Accept-Language: en-US,en;q=0.9',
                url
            ],
            capture_output=True,
            text=True,
            timeout=timeout + 5
        )
        if result.returncode == 0 and result.stdout and not result.stdout.startswith('429'):
            return result.stdout
    except Exception:
        pass
    return None

def search_tpb(query: str, category: int = 207) -> List[Dict]:
    """Search TPB for torrents matching query (Default: HD Movies 207)."""
    # Check cache first
    cache_key = get_cache_key(f'tpb_{category}', query)
    cached = get_cached(cache_key)
    if cached:
        try:
            return json.loads(cached)
        except:
            pass
    
    encoded_query = urllib.parse.quote_plus(query)
    url = f"{TPB_SEARCH_URL}?q={encoded_query}&cat={category}"
    
    # Use curl for TPB (better at avoiding rate limits)
    response = fetch_url_curl(url, timeout=8)
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
# EZTV API (Dedicated TV Shows Source)
# ═══════════════════════════════════════════════════════════════

# EZTV domains in order of preference (ISPs block these rotationally)
EZTV_DOMAINS = ['eztv.yt', 'eztv1.xyz', 'eztv.tf', 'eztvx.to', 'eztv.re']

def fetch_eztv_shows(limit: int = 50, page: int = 1) -> List[Dict]:
    """
    Fetch latest TV shows from EZTV API with domain rotation.
    Returns list of torrent dicts with normalized field names.
    """
    cache_key = get_cache_key('eztv_shows', f'{limit}_{page}')
    cached = get_cached(cache_key)
    if cached:
        try:
            return json.loads(cached)
        except:
            pass
    
    # Try each EZTV domain until one works
    response = None
    for domain in EZTV_DOMAINS:
        url = f"https://{domain}/api/get-torrents?limit={limit}&page={page}"
        response = fetch_url(url, timeout=6)
        if response:
            break  # Found a working domain
    
    if not response:
        return []
    
    try:
        data = json.loads(response)
        torrents_raw = data.get('torrents', [])
        
        results = []
        for t in torrents_raw[:limit]:
            # Normalize to TPB-like format
            info_hash = t.get('hash', '')
            if not info_hash:
                continue
                
            results.append({
                'source': 'EZTV',
                'name': t.get('title', t.get('filename', 'Unknown')),
                'info_hash': info_hash.upper(),
                'seeders': int(t.get('seeds', 0)),
                'size': int(t.get('size_bytes', 0)),
                'imdb': t.get('imdb_id', 'N/A')
            })
        
        if results:
            set_cache(cache_key, json.dumps(results))
        return results
        
    except Exception:
        return []


def search_eztv(query: str) -> List[Dict]:
    """Search EZTV for TV show torrents by IMDB ID."""
    cache_key = get_cache_key('eztv_search', query)
    cached = get_cached(cache_key)
    if cached:
        try:
            return json.loads(cached)
        except:
            pass
    
    # EZTV doesn't have a text search API - only IMDB-based search works
    if query.startswith('tt'):
        imdb_num = query.replace('tt', '')
    else:
        # No direct text search, return empty (will rely on TPB for text search)
        return []
    
    # Try each EZTV domain until one works
    response = None
    for domain in EZTV_DOMAINS:
        url = f"https://{domain}/api/get-torrents?imdb_id={imdb_num}&limit=50"
        response = fetch_url(url, timeout=6)
        if response:
            break
    
    if not response:
        return []
    
    try:
        data = json.loads(response)
        torrents_raw = data.get('torrents', [])
        
        results = []
        for t in torrents_raw:
            info_hash = t.get('hash', '')
            if not info_hash:
                continue
                
            results.append({
                'source': 'EZTV',
                'name': t.get('title', t.get('filename', 'Unknown')),
                'info_hash': info_hash.upper(),
                'seeders': int(t.get('seeds', 0)),
                'size': int(t.get('size_bytes', 0)),
                'imdb': t.get('imdb_id', 'N/A'),
                'magnet': t.get('magnet_url', f"magnet:?xt=urn:btih:{info_hash}")
            })
        
        if results:
            set_cache(cache_key, json.dumps(results))
        return results
        
    except Exception:
        return []


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
        raw_items = []
        
        # Regex to detect TV Shows (Season/Episode patterns)
        tv_pattern = re.compile(r'(S\d{1,2}E\d{1,2}|Season\s*\d+|Complete\s*Series|(\d+)x(\d+))', re.IGNORECASE)
        
        for item in data[:limit * 2]: # Fetch more to allow for filtering/grouping
            info_hash = item.get('info_hash', '')
            if not info_hash or info_hash == '0' * 40:
                continue
            
            name = item.get('name', 'Unknown')
            
            # Strict Content Filtering: If we are asking for Movies (201/207), 
            # reject anything looking like a TV show.
            is_tv = tv_pattern.search(name)
            if category in [201, 207, 209, 202] and is_tv:
                continue
            
            raw_items.append(item)

        if category in [205, 208]: # TV Shows Categories
            # PARALLEL MULTI-SOURCE FETCH
            # Fetch from TPB HD, TPB non-HD, and EZTV concurrently
            all_items = []
            
            def fetch_tpb_category(cat: int) -> List[Dict]:
                """Fetch TPB top100 for given category."""
                url = f'https://apibay.org/precompiled/data_top100_{cat}.json'
                response = fetch_url(url, timeout=8)
                if not response:
                    return []
                try:
                    data = json.loads(response)
                    items = []
                    for item in data[:100]:
                        info_hash = item.get('info_hash', '')
                        if info_hash and info_hash != '0' * 40:
                            item['source'] = 'TPB'
                            items.append(item)
                    return items
                except:
                    return []
            
            # Add TPB HD items we already fetched
            for item in raw_items:
                item['source'] = 'TPB'
            all_items.extend(raw_items)
            
            # Parallel fetch: TPB non-HD + EZTV
            with ThreadPoolExecutor(max_workers=3) as executor:
                futures = {
                    executor.submit(fetch_tpb_category, 205): 'TPB_NonHD',
                    executor.submit(fetch_eztv_shows, 100): 'EZTV',
                }
                for future in as_completed(futures, timeout=12):
                    source_name = futures[future]
                    try:
                        items = future.result(timeout=10)
                        if items:
                            all_items.extend(items)
                    except Exception:
                        pass  # Source failed, continue with others
            
            return group_shows_by_series(all_items, limit)
        
        # Standard movie processing for TPB fallback
        results = []
        for item in raw_items[:limit]:
            info_hash = item.get('info_hash', '')
            name = item.get('name', 'Unknown')
            seeders = int(item.get('seeders', 0))
            size_bytes = int(item.get('size', 0))
            size_mb = size_bytes // (1024 * 1024)
            size_str = f"{size_mb}MB" if size_mb < 1024 else f"{size_mb/1024:.1f}GB"
            quality = extract_quality(name)
            magnet = f"magnet:?xt=urn:btih:{info_hash}"
            imdb = item.get('imdb', 'N/A')
            
            combined = (
                f"COMBINED|{name}|"
                f"TPB|"
                f"{quality}|"
                f"{seeders}|"
                f"{size_str}|"
                f"{magnet}|"
                f"N/A|"
                f"{imdb}|"
                f"Movies|"
                f"1"
            )
            results.append(combined)
        return results

    except Exception:
        return []

def normalize_series_name(name: str) -> str:
    """Normalize series name for consistent grouping."""
    # Primary strategy: Extract just the series name BEFORE episode/season markers
    # Pattern matches: "Show Name S01E01...", "Show.Name.S01...", "Show Name 1x01..."
    
    # Try to extract series name before episode marker
    series_match = re.match(r'^(.+?)[\.\s]+(?:S\d{1,2}(?:E\d{1,4})?|\d+x\d+|Season\s*\d+)', name, re.IGNORECASE)
    if series_match:
        name = series_match.group(1)
    
    # Remove release group at end (e.g., -MeGusta, -ETHEL)
    name = re.sub(r'-[A-Za-z0-9]+$', '', name)
    
    # Remove quality/codec patterns that might still be in prefix
    name = re.sub(r'[\.\s]+(1080p|720p|480p|2160p|4K)', '', name, flags=re.IGNORECASE)
    
    # Remove bracketed/parenthesized content
    name = re.sub(r'\[.*?\]', '', name)
    name = re.sub(r'\(.*?\)', '', name)
    
    # Remove trailing year (e.g., "Show Name 2024")
    name = re.sub(r'[\.\s]+(?:19|20)\d{2}$', '', name)
    
    # Replace dots/underscores with spaces
    name = name.replace('.', ' ').replace('_', ' ')
    
    # Clean up whitespace and trailing dashes
    name = re.sub(r'[-\s]+$', '', name)
    name = re.sub(r'\s+', ' ', name).strip()
    
    # Title case for consistency
    name = name.title()
    
    return name


def group_shows_by_series(items: List[Dict], limit: int) -> List[str]:
    """Group individual TV torrents by series title."""
    from collections import defaultdict
    series_groups = defaultdict(list)
    
    for item in items:
        raw_name = item.get('name', 'Unknown')
        series_name = normalize_series_name(raw_name)
        
        # Skip if normalization resulted in empty string
        if not series_name:
            continue
            
        series_groups[series_name].append(item)
    
    results = []
    # Sort series by the highest seeds in any of its torrents
    sorted_series = sorted(series_groups.items(), 
                          key=lambda x: max(int(i.get('seeders', i.get('seeds', 0))) for i in x[1]), 
                          reverse=True)
    
    for series_name, torrents in sorted_series[:limit]:
        # Aggregate data for Stage 1
        # Handle both TPB format (info_hash) and EZTV format (hash)
        sources = [t.get('source', 'TPB') for t in torrents]
        qualities = [extract_quality(t.get('name', '')) for t in torrents]
        seeds = [str(t.get('seeders', t.get('seeds', 0))) for t in torrents]
        sizes = []
        for t in torrents:
            size_bytes = int(t.get('size', t.get('size_bytes', 0)))
            size_mb = size_bytes // (1024 * 1024)
            sizes.append(f"{size_mb}MB" if size_mb < 1024 else f"{size_mb/1024:.1f}GB")
        
        # Handle both hash field names
        magnets = []
        for t in torrents:
            h = t.get('info_hash', t.get('hash', ''))
            if h:
                magnets.append(f"magnet:?xt=urn:btih:{h}")
        
        imdb = torrents[0].get('imdb', 'N/A')
        
        # For the display name in Stage 1, use the Series Name
        # Create a combined standard item
        title = f"{series_name}"
        combined = (
            f"COMBINED|{title}|"
            f"{'^'.join(sources)}|"
            f"{'^'.join(qualities)}|"
            f"{'^'.join(seeds)}|"
            f"{'^'.join(sizes)}|"
            f"{'^'.join(magnets)}|"
            f"N/A|"  # Poster TBD
            f"{imdb}|"
            f"Shows|"
            f"{len(torrents)}"
        )
        results.append(combined)
        
    return results

def group_movies_by_title(items: List[Dict], limit: int) -> List[str]:
    """Group individual movie torrents from TPB by title."""
    from collections import defaultdict
    movie_groups = defaultdict(list)
    
    # Pattern to extract title and optional year: "Title (2024)" or "Title.2024"
    # Note: For movies we usually want to group by exact Title + Year if possible
    movie_pattern = re.compile(r'^(.+?)([\s\.](19|20)\d{2}|[\s\.](720|1080|2160)p|$)', re.IGNORECASE)
    
    for item in items:
        name = item.get('name', 'Unknown')
        match = movie_pattern.search(name)
        if match:
            clean_name = match.group(1).replace('.', ' ').strip()
            # Extract year if present in original name
            year_match = re.search(r'(19|20)\d{2}', name)
            group_key = f"{clean_name} ({year_match.group(0)})" if year_match else clean_name
        else:
            group_key = name
            
        movie_groups[group_key].append(item)
    
    results = []
    # Sort by highest seeds
    sorted_movies = sorted(movie_groups.items(), 
                           key=lambda x: max(int(i.get('seeders', 0)) for i in x[1]), 
                           reverse=True)
    
    for movie_title, torrents in sorted_movies[:limit]:
        sources = ["TPB"] * len(torrents)
        qualities = [extract_quality(t.get('name', '')) for t in torrents]
        seeds = [str(t.get('seeders', 0)) for t in torrents]
        sizes = []
        for t in torrents:
            size_bytes = int(t.get('size', 0))
            size_mb = size_bytes // (1024 * 1024)
            sizes.append(f"{size_mb}MB" if size_mb < 1024 else f"{size_mb/1024:.1f}GB")
        
        magnets = [f"magnet:?xt=urn:btih:{t.get('info_hash')}" for t in torrents]
        imdb = torrents[0].get('imdb', 'N/A')
        
        combined = (
            f"COMBINED|{movie_title}|"
            f"{'^'.join(sources)}|"
            f"{'^'.join(qualities)}|"
            f"{'^'.join(seeds)}|"
            f"{'^'.join(sizes)}|"
            f"{'^'.join(magnets)}|"
            f"N/A|"
            f"{imdb}|"
            f"Movies|"
            f"{len(torrents)}"
        )
        results.append(combined)
        
    return results

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
    # If query is provided, perform a targeted search instead of fetching newest
    if query_term:
        if category_mode == 'movies':
            # Movies: Search YTS first
            movies = fetch_yts_movies(limit=limit, page=page, sort_by=sort_by, 
                                      query_term=query_term, genre=genre, min_rating=min_rating,
                                      order_by=order_by)
            if not movies:
                # Fallback: Search TPB Movies
                tpb_cat = 207 # HD Movies
                items = search_tpb(query_term, category=tpb_cat)
                return group_movies_by_title(items, limit)
        else:
            # Shows: Search TPB Shows - return INDIVIDUAL torrents for version picker
            tpb_cat = 208  # HD TV Shows
            items = search_tpb(query_term, category=tpb_cat)
            # For episode search, return each torrent as a separate COMBINED entry (like movies)
            # This allows the version picker to list individual quality options
            results = []
            for item in items[:limit]:
                name = item.get('name', 'Unknown')
                quality = item.get('quality', extract_quality(name))
                seeds = str(item.get('seeds', 0))
                size = item.get('size', 'N/A')
                magnet = item.get('magnet', '')
                
                combined = (
                    f"COMBINED|{name}|"
                    f"TPB|"
                    f"{quality}|"
                    f"{seeds}|"
                    f"{size}|"
                    f"{magnet}|"
                    f"N/A|"
                    f"N/A|"
                    f"Shows|"
                    f"1"
                )
                results.append(combined)
            return results

    # NO QUERY: Fetch Latest/Trending Catalog
    movies = []
    if category_mode == 'movies':
        movies = fetch_yts_movies(limit=limit, page=page, sort_by=sort_by, 
                                  query_term=query_term, genre=genre, min_rating=min_rating,
                                  order_by=order_by)
    
    # FALLBACK: If YTS fails or we want SHOWS, use TPB precompiled (Newest)
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
