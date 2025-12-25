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
from datetime import datetime
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

        cleaned = clean_display_title(group_key)
        if cleaned:
            group_key = cleaned
            
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
        display_title = clean_display_title(movie_title) or movie_title
        
        combined = (
            f"COMBINED|{display_title}|"
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
# NEW ENRICHED CATALOG ALGORITHM
# ═══════════════════════════════════════════════════════════════

def normalize_movie_title(name: str) -> str:
    """Normalize movie title for deduplication (lowercase, stripped, no punctuation).
    
    Key normalizations:
    - Remove quality markers, release groups, bracketed content
    - Remove punctuation (colons, apostrophes, etc.) for cross-source matching
    - Extract and append year at the end for consistency
    """
    # Extract year first (for consistent comparison)
    year_match = re.search(r'\(?((19|20)\d{2})\)?', name)
    year = year_match.group(1) if year_match else ''
    
    # Remove quality markers, release groups, etc.
    name = re.sub(r'[\.\s]+(1080p|720p|480p|2160p|4K|HDRip|BRRip|BluRay|WEB-DL|WEBRip|HDTV|x264|x265|HEVC|AAC|DTS)', '', name, flags=re.IGNORECASE)
    name = re.sub(r'-[A-Za-z0-9]+$', '', name)  # Release group
    name = re.sub(r'\[.*?\]', '', name)  # Bracketed content
    name = re.sub(r'\((?:19|20)\d{2}\)', '', name)  # Remove year in parens (we add back normalized)
    name = re.sub(r'\([^)]*\)', '', name)  # Other parentheses  
    
    # Remove punctuation that differs between sources (colons, apostrophes, etc.)
    name = re.sub(r'[:\'"''""`]', '', name)  # Remove quotes and colons
    
    name = name.replace('.', ' ').replace('_', ' ')
    name = re.sub(r'\s+', ' ', name).strip()
    
    # Normalize to lowercase and append year for consistent matching
    normalized = name.lower()
    if year:
        normalized = f"{normalized} {year}"
    
    return normalized


def clean_display_title(name: str) -> str:
    """
    Clean TPB torrent name for display and API lookups.
    
    TPB naming pattern: [TITLE] [SEP] [YEAR] [SEP] [TECH_SPECS] [-RELEASE_GROUP]
    
    Strategy: Extract everything BEFORE the year as the title, then format as "Title (Year)"
    This is far more reliable than pattern-matching tech specs.
    
    Examples:
        "Predator Badlands 2025 1080p HDRip HEVC x265 BONE" -> "Predator Badlands (2025)"
        "Wake.Up.Dead.Man.A.Knives.Out.Mystery.2025.1080p.NF.WEB-DL" -> "Wake Up Dead Man A Knives Out Mystery (2025)"
        "Predator Badlands (2025) [1080p] [WEBRip]" -> "Predator Badlands (2025)"
        "Home Alone (1990) 1080p BrRip x264 - YIFY" -> "Home Alone (1990)"
    """
    original = name
    
    # Step 1: Remove bracketed content like [1080p], [WEBRip], [5.1], [YTS.MX]
    name = re.sub(r'\s*\[.*?\]', '', name)
    
    # Step 2: Replace dots and underscores with spaces
    name = name.replace('.', ' ').replace('_', ' ')
    
    # Step 3: Try to find year and extract title before it
    # Pattern: look for year (1920-2029) that's followed by tech specs or end
    year_match = re.search(r'[\s\(]+((?:19[2-9]\d|20[0-2]\d))(?:[\s\)\]]|$)', name)
    
    if year_match:
        year = year_match.group(1)
        title = name[:year_match.start()].strip()
        
        # Clean up title - remove residual tech specs that may be in already-processed names
        # (e.g., "Nuremberg 5 1" from "Nuremberg 5.1" where dots were already replaced)
        residual_patterns = [
            r'\s+5\s*1(?:\s|$)',       # 5.1 audio -> " 5 1"
            r'\s+7\s*1(?:\s|$)',       # 7.1 audio
            r'\s+2\s*0(?:\s|$)',       # 2.0 audio
            r'\s+H\s*26\d?(?:\s|$)',   # H.264/H.265 -> "H 264" or "H 26"
            r'\s+Dd5?\s*1?(?:\s|$)',   # DD5.1 -> "Dd5 1" or "Dd 5 1"
            r'\s+Ddp\d?\s*1?(?:\s|$)', # DDP5.1 -> "Ddp5 1"
            r'\s+Nf(?:\s|$)',          # Netflix marker
            r'\s+Ma(?:\s|$)',          # MA marker
            r'\s+Hc(?:\s|$)',          # HC (hardcoded) marker
            r'\s+\d+Bits?(?:\s|$)',    # 10Bits, 8Bits
            r'\s+Chinese(?:\s|$)',     # Language marker
            r'\s+Korean(?:\s|$)',      # Language marker
            r'\s+En(?:\s|$)',          # English marker
        ]
        for pattern in residual_patterns:
            title = re.sub(pattern, ' ', title, flags=re.IGNORECASE)
        
        # Clean up title
        title = re.sub(r'\s+', ' ', title).strip()
        title = re.sub(r'[\s\-:]+$', '', title)  # Remove trailing punctuation
        
        if title:
            # Title case and format
            title = title.title()
            
            # Fix common title case issues
            title = re.sub(r'\bOf\b', 'of', title)
            title = re.sub(r'\bThe\b', 'The', title)
            title = re.sub(r'\bA\b', 'a', title)
            title = re.sub(r'\bAn\b', 'an', title)
            title = re.sub(r'\bAnd\b', 'and', title)
            title = re.sub(r'\bIn\b', 'in', title)
            title = re.sub(r'\bOn\b', 'on', title)
            title = re.sub(r'\bTo\b', 'to', title)
            title = re.sub(r'\bFor\b', 'for', title)
            title = re.sub(r'\bAt\b', 'at', title)
            
            # Capitalize first letter
            if title:
                title = title[0].upper() + title[1:]
            
            return f"{title} ({year})"
    
    # Fallback: If no year found, try to extract title before common tech markers
    tech_markers = [
        r'\b1080p\b', r'\b720p\b', r'\b2160p\b', r'\b480p\b', r'\b4K\b',
        r'\bHDRip\b', r'\bWEBRip\b', r'\bWEB-DL\b', r'\bBluRay\b', r'\bBRRip\b',
        r'\bHDTV\b', r'\bCAM\b', r'\bTS\b', r'\bTC\b',
        r'\bx264\b', r'\bx265\b', r'\bHEVC\b', r'\bH\s*264\b', r'\bH\s*265\b',
    ]
    
    for marker in tech_markers:
        match = re.search(marker, name, re.IGNORECASE)
        if match and match.start() > 5:  # Ensure we have some title
            title = name[:match.start()].strip()
            title = re.sub(r'[\s\-:]+$', '', title)
            
            if title:
                title = title.title()
                if title:
                    title = title[0].upper() + title[1:]
                return title
    
    # Last resort: just clean up and return
    name = re.sub(r'\s+', ' ', name).strip()
    name = name.title()
    if name:
        name = name[0].upper() + name[1:]
    return name



def fetch_tpb_top100_movies() -> List[Dict]:
    """
    Fetch TPB top 100 HD movies (precompiled).
    Returns list of dicts with normalized fields.
    """
    TPB_TOP100_URL = 'https://apibay.org/precompiled/data_top100_207.json'
    response = fetch_url(TPB_TOP100_URL, timeout=10)
    if not response:
        return []
    
    try:
        data = json.loads(response)
        movies = []
        
        # Regex to detect TV Shows
        tv_pattern = re.compile(r'(S\d{1,2}E\d{1,2}|Season\s*\d+|Complete\s*Series|\d+x\d+)', re.IGNORECASE)
        
        for item in data[:100]:
            info_hash = item.get('info_hash', '')
            if not info_hash or info_hash == '0' * 40:
                continue
            
            name = item.get('name', 'Unknown')
            
            # Skip TV shows
            if tv_pattern.search(name):
                continue
            
            # Extract year from name
            year_match = re.search(r'(19|20)\d{2}', name)
            year = year_match.group(0) if year_match else ''
            
            # Generate clean search title for YTS/API lookups
            cleaned = clean_display_title(name)
            # Extract just the title part (without year) for searching
            search_title = re.sub(r'\s*\(\d{4}\)\s*$', '', cleaned).strip()
            
            movies.append({
                'name': name,
                'clean_title': search_title.lower(),  # For deduplication
                'search_title': search_title,          # For YTS/TPB search
                'display_name': cleaned,               # For display (with year)
                'year': year,
                'info_hash': info_hash.lower(),
                'seeders': int(item.get('seeders', 0)),
                'size': int(item.get('size', 0)),
                'imdb': item.get('imdb', ''),
                'source': 'TPB'
            })
        
        return movies
    except Exception:
        return []


def enrich_movie_with_sources(movie: Dict) -> Dict:
    """
    Enrich a movie with additional sources from TPB search and YTS search.
    Returns movie dict with 'torrents' list containing all sources.
    """
    # Use search_title if available (from TPB), otherwise clean_title
    title = movie.get('search_title', movie.get('clean_title', movie.get('name', '')))
    year = movie.get('year', '')
    search_query = f"{title} {year}".strip()
    
    torrents = []
    
    # Add original TPB torrent if present
    if movie.get('info_hash'):
        size_bytes = int(movie.get('size', 0))
        size_mb = size_bytes // (1024 * 1024)
        torrents.append({
            'source': 'TPB',
            'hash': movie['info_hash'],
            'quality': extract_quality(movie.get('name', '')),
            'size': f"{size_mb}MB" if size_mb < 1024 else f"{size_mb/1024:.1f}GB",
            'seeds': movie.get('seeders', 0),
            'magnet': f"magnet:?xt=urn:btih:{movie['info_hash']}"
        })
    
    # Search TPB for more sources
    tpb_results = search_tpb(search_query, category=207)
    for t in tpb_results:
        if t.get('hash') and t['hash'] not in [x['hash'] for x in torrents]:
            torrents.append(t)
    
    # Search YTS for sources
    yts_results = search_yts(search_query)
    for t in yts_results:
        if t.get('hash') and t['hash'] not in [x['hash'] for x in torrents]:
            torrents.append(t)
    
    movie['torrents'] = torrents
    return movie


def aggregate_movie(movie: Dict) -> Optional[str]:
    """
    Aggregate torrents from YTS and TPB for a single movie (for search).
    Returns COMBINED format string.
    """
    title = movie.get('title', '')
    year = movie.get('year', '')
    poster = movie.get('medium_cover_image', 'N/A')
    rating = movie.get('rating', 0)
    
    if not title:
        return None
    
    # Collect YTS torrents from this movie
    all_torrents = parse_yts_torrents(movie)
    
    # Search query for additional sources
    search_query = f"{title} {year}"
    
    # Search TPB for additional torrents
    tpb_torrents = search_tpb(search_query)
    
    # Deduplicate by hash
    seen_hashes = {t['hash'] for t in all_torrents}
    
    for t in tpb_torrents:
        if t.get('hash') and t['hash'] not in seen_hashes and t.get('source'):
            all_torrents.append(t)
            seen_hashes.add(t['hash'])
    
    if not all_torrents:
        return None
    
    # Filter out torrents with empty source
    all_torrents = [t for t in all_torrents if t.get('source')]
    
    if not all_torrents:
        return None
    
    # Sort by seeds (descending)
    all_torrents.sort(key=lambda x: x.get('seeds', 0), reverse=True)
    
    # Format arrays for COMBINED output
    per_torrent_sources = [t['source'] for t in all_torrents]
    qualities = [t.get('quality', 'Unknown') for t in all_torrents]
    seeds = [str(t.get('seeds', 0)) for t in all_torrents]
    sizes = [t.get('size', 'N/A') for t in all_torrents]
    magnets = [t.get('magnet', '') for t in all_torrents]
    
    rating_str = f"{rating}/10" if rating else 'N/A'
    genres = movie.get('genres', [])
    genre_str = ', '.join(genres) if genres else 'Unknown'
    
    display_title = f"{title} ({year})"
    combined = (
        f"COMBINED|{display_title}|"
        f"{'^'.join(per_torrent_sources)}|"
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


def fetch_enriched_catalog(limit: int = 50, page: int = 1, sort_by: str = 'date_added',
                           query_term: str = None, genre: str = None, min_rating: int = 0,
                           order_by: str = 'desc', category_mode: str = 'movies',
                           yts_pages: int = 10, start_page: int = 1, skip_tpb: bool = False) -> List[str]:
    """
    NEW ALGORITHM:
    1. Fetch TPB top 100 HD movies (popular/trending base)
    2. For each: search TPB + YTS for all sources
    3. Fetch YTS pages 1-10 (or custom) for latest content
    4. Combine, dedupe by normalized title, sort
    5. Return COMBINED format strings
    
    Args:
        limit: Items per page for display
        page: Page number for display
        yts_pages: Number of YTS pages to fetch (default 10)
    """
    # Handle search queries separately
    if query_term:
        if category_mode == 'movies':
            movies = fetch_yts_movies(limit=limit, page=page, sort_by=sort_by,
                                      query_term=query_term, genre=genre, min_rating=min_rating,
                                      order_by=order_by)
            if not movies:
                items = search_tpb(query_term, category=207)
                return group_movies_by_title([{'source': 'TPB', **i} for i in items], limit)
            
            results = []
            for movie in movies:
                result = aggregate_movie(movie)
                if result:
                    results.append(result)
            return results
        else:
            # Shows search
            tpb_cat = 208
            items = search_tpb(query_term, category=tpb_cat)
            results = []
            for item in items[:limit]:
                name = item.get('name', 'Unknown')
                quality = item.get('quality', extract_quality(name))
                combined = (
                    f"COMBINED|{name}|"
                    f"TPB|{quality}|{item.get('seeds', 0)}|{item.get('size', 'N/A')}|"
                    f"{item.get('magnet', '')}|N/A|N/A|Shows|1"
                )
                results.append(combined)
            return results
    
    # Handle TV Shows separately (use existing logic)
    if category_mode == 'shows':
        return fetch_tpb_fallback_catalog(limit * 2, category=208)
    
    # ═══════════════════════════════════════════════════════════════
    # PHASE 1: Fetch TPB Top 100 Movies (skip if start_page > 1 for incremental fetch)
    # ═══════════════════════════════════════════════════════════════
    all_movies = {}  # Keyed by normalized title for deduplication
    
    # Only fetch TPB on initial load (start_page == 1), not on incremental prefetch
    tpb_top100 = [] if skip_tpb or start_page > 1 else fetch_tpb_top100_movies()
    
    # Enrich TPB movies with additional sources (parallel)
    with ThreadPoolExecutor(max_workers=15) as executor:
        futures = {executor.submit(enrich_movie_with_sources, m): m for m in tpb_top100}
        for future in as_completed(futures, timeout=30):
            try:
                enriched = future.result(timeout=5)
                if enriched and enriched.get('torrents'):
                    key = normalize_movie_title(enriched.get('name', ''))
                    if key not in all_movies:
                        all_movies[key] = enriched
                    else:
                        # Merge torrents
                        existing_hashes = {t['hash'] for t in all_movies[key].get('torrents', [])}
                        for t in enriched.get('torrents', []):
                            if t['hash'] not in existing_hashes:
                                all_movies[key]['torrents'].append(t)
            except Exception:
                pass
    
    # ═══════════════════════════════════════════════════════════════
    # PHASE 2: Fetch YTS Latest Pages 1-N
    # ═══════════════════════════════════════════════════════════════
    def fetch_and_enrich_yts_page(p: int) -> List[Dict]:
        """Fetch a YTS page and enrich each movie."""
        movies = fetch_yts_movies(limit=50, page=p, sort_by=sort_by, 
                                  genre=genre, min_rating=min_rating, order_by=order_by)
        enriched = []
        for movie in movies:
            title = movie.get('title', '')
            year = movie.get('year', '')
            
            # Parse YTS torrents
            torrents = parse_yts_torrents(movie)
            
            # Search TPB for additional sources
            tpb_results = search_tpb(f"{title} {year}", category=207)
            seen_hashes = {t['hash'] for t in torrents}
            for t in tpb_results:
                if t.get('hash') and t['hash'] not in seen_hashes:
                    torrents.append(t)
                    seen_hashes.add(t['hash'])
            
            enriched.append({
                'name': f"{title} ({year})",
                'clean_title': title.lower(),
                'year': str(year),
                'torrents': torrents,
                'poster': movie.get('medium_cover_image', 'N/A'),
                'rating': movie.get('rating', 0),
                'genres': movie.get('genres', []),
                'imdb': movie.get('imdb_code', '')
            })
        return enriched
    
    # Parallel fetch YTS pages (from start_page to yts_pages inclusive)
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = {executor.submit(fetch_and_enrich_yts_page, p): p for p in range(start_page, yts_pages + 1)}
        for future in as_completed(futures, timeout=60):
            try:
                page_movies = future.result(timeout=15)
                for movie in page_movies:
                    key = normalize_movie_title(movie.get('name', ''))
                    if key not in all_movies:
                        all_movies[key] = movie
                    else:
                        # Merge torrents and prefer YTS metadata (has poster, rating, etc.)
                        existing = all_movies[key]
                        existing_hashes = {t['hash'] for t in existing.get('torrents', [])}
                        for t in movie.get('torrents', []):
                            if t['hash'] not in existing_hashes:
                                existing['torrents'].append(t)
                        # Update metadata if YTS has better info
                        if movie.get('poster') and movie['poster'] != 'N/A':
                            existing['poster'] = movie['poster']
                        if movie.get('rating'):
                            existing['rating'] = movie['rating']
                        if movie.get('genres'):
                            existing['genres'] = movie['genres']
            except Exception:
                pass
    
    # ═══════════════════════════════════════════════════════════════
    # PHASE 3: Convert to COMBINED format
    # ═══════════════════════════════════════════════════════════════
    results = []
    
    for key, movie in all_movies.items():
        torrents = movie.get('torrents', [])
        if not torrents:
            continue
        
        # Sort torrents by seeds
        torrents.sort(key=lambda x: int(x.get('seeds', 0)), reverse=True)
        
        # Build COMBINED arrays
        sources = [t['source'] for t in torrents]
        qualities = [t.get('quality', 'Unknown') for t in torrents]
        seeds = [str(t.get('seeds', 0)) for t in torrents]
        sizes = [t.get('size', 'N/A') for t in torrents]
        magnets = [t.get('magnet', '') for t in torrents]
        
        # Get metadata
        poster = movie.get('poster', 'N/A')
        rating = movie.get('rating', 0)
        rating_str = f"{rating}/10" if rating else 'N/A'
        genres = movie.get('genres', [])
        genre_str = ', '.join(genres) if genres else 'Unknown'
        
        # Clean the display title (removes [1080p] [WEBRip] etc.)
        raw_title = movie.get('name', key)
        display_title = clean_display_title(raw_title)
        
        combined = (
            f"COMBINED|{display_title}|"
            f"{'^'.join(sources)}|"
            f"{'^'.join(qualities)}|"
            f"{'^'.join(seeds)}|"
            f"{'^'.join(sizes)}|"
            f"{'^'.join(magnets)}|"
            f"{poster}|"
            f"{rating_str}|"
            f"{genre_str}|"
            f"{len(torrents)}"
        )
        results.append(combined)
    
    # ═══════════════════════════════════════════════════════════════
    # PHASE 4: Sort by year (newest first), then by max seeds
    # ═══════════════════════════════════════════════════════════════
    def extract_year_from_combined(entry):
        try:
            parts = entry.split('|')
            if len(parts) > 1:
                match = re.search(r'\((\d{4})\)', parts[1])
                if match:
                    return int(match.group(1))
        except:
            pass
        return 0
    
    def extract_max_seeds(entry):
        try:
            parts = entry.split('|')
            if len(parts) > 4:
                seeds = parts[4].split('^')
                return max(int(s) for s in seeds if s.isdigit())
        except:
            pass
        return 0
    
    # Sort by year desc, then by seeds desc
    results.sort(key=lambda x: (extract_year_from_combined(x), extract_max_seeds(x)), reverse=True)
    
    return results


# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Multi-source catalog fetcher (New Algorithm)')
    parser.add_argument('--limit', type=int, default=50, help='Movies per display page')
    parser.add_argument('--page', type=int, default=1, help='Display page number')
    parser.add_argument('--sort', type=str, default='date_added', 
                        choices=['date_added', 'download_count', 'rating', 'seeds', 'peers', 'year'],
                        help='Sort method')
    parser.add_argument('--query', type=str, default=None, help='Search query')
    parser.add_argument('--genre', type=str, default=None, help='Filter by genre')
    parser.add_argument('--min-rating', type=int, default=0, help='Minimum rating (0-9)')
    parser.add_argument('--order-by', type=str, default='desc', help='Sort order (desc/asc)')
    parser.add_argument('--category', type=str, default='movies', help='Category mode (movies/shows)')
    parser.add_argument('--yts-pages', type=int, default=10, help='Number of YTS pages to fetch (default 10)')
    parser.add_argument('--start-page', type=int, default=1, help='Start page for YTS (for incremental fetch, default 1)')
    parser.add_argument('--skip-tpb', action='store_true', help='Skip TPB fetch (for incremental updates)')
    parser.add_argument('--refresh', action='store_true', help='Force refresh cache (ignore cached data)')
    parser.add_argument('--json-export', type=str, default=None, help='Export all fetched data to JSON file for analysis')
    
    args = parser.parse_args()
    
    # Set global flags
    global REFRESH_CACHE
    REFRESH_CACHE = args.refresh
    
    # Fetch Catalog using NEW enriched algorithm
    catalog = fetch_enriched_catalog(
        limit=args.limit,
        page=args.page,
        sort_by=args.sort,
        query_term=args.query,
        genre=args.genre,
        min_rating=args.min_rating,
        order_by=args.order_by,
        category_mode=args.category,
        yts_pages=args.yts_pages,
        start_page=args.start_page,
        skip_tpb=args.skip_tpb
    )
    
    # Export to JSON if requested
    if args.json_export:
        import json
        export_data = []
        for line in catalog:
            parts = line.split('|')
            if len(parts) >= 10 and parts[0] == 'COMBINED':
                export_data.append({
                    'type': parts[0],
                    'title': parts[1],
                    'sources': parts[2].split('^') if parts[2] else [],
                    'qualities': parts[3].split('^') if parts[3] else [],
                    'seeds': parts[4].split('^') if parts[4] else [],
                    'sizes': parts[5].split('^') if parts[5] else [],
                    'magnets': parts[6].split('^') if parts[6] else [],
                    'poster': parts[7],
                    'rating': parts[8],
                    'genres': parts[9],
                    'torrent_count': parts[10] if len(parts) > 10 else '0',
                    'raw_line': line
                })
        
        with open(args.json_export, 'w') as f:
            json.dump({
                'total_movies': len(export_data),
                'export_time': str(datetime.now()),
                'args': {
                    'yts_pages': args.yts_pages,
                    'category': args.category,
                    'sort': args.sort
                },
                'movies': export_data
            }, f, indent=2)
        
        print(f"Exported {len(export_data)} movies to {args.json_export}", file=sys.stderr)
    else:
        for line in catalog:
            print(line, flush=True)

if __name__ == '__main__':
    main()
