#!/usr/bin/env python3
"""
Jackett/Prowlarr Integration for Termflix
Searches torrents via Jackett or Prowlarr API
Now includes YTS poster fetching for enhanced display
"""
import sys
import os
import json
import urllib.request
import urllib.parse
import urllib.error
import re
from concurrent.futures import ThreadPoolExecutor, as_completed

# Cache for YTS poster lookups (title -> poster_url)
_poster_cache = {}

def extract_movie_info(title):
    """Extract movie name and year from torrent title"""
    # Pattern: "Movie Name (2024)" or "Movie.Name.2024.1080p..."
    # Try parentheses first
    match = re.search(r'^(.+?)\s*\((\d{4})\)', title)
    if match:
        return match.group(1).strip(), match.group(2)
    
    # Try dot/space separated year
    match = re.search(r'^(.+?)[\.\s]+(\d{4})[\.\s]', title)
    if match:
        name = match.group(1).replace('.', ' ').strip()
        return name, match.group(2)
    
    # Just try to find a year anywhere
    match = re.search(r'(\d{4})', title)
    if match:
        year = match.group(1)
        name = title.split(year)[0].replace('.', ' ').strip()
        return name, year
    
    return title.replace('.', ' ').strip(), None

def fetch_yts_poster(movie_name, year=None):
    """Fetch poster URL from YTS API for a given movie"""
    if not movie_name:
        return None
    
    cache_key = f"{movie_name}_{year}"
    if cache_key in _poster_cache:
        return _poster_cache[cache_key]
    
    try:
        # Build YTS search query
        query = movie_name
        params = {
            'query_term': query,
            'limit': 1
        }
        url = f"https://yts.mx/api/v2/list_movies.json?{urllib.parse.urlencode(params)}"
        
        req = urllib.request.Request(url, headers={
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
        })
        
        with urllib.request.urlopen(req, timeout=3) as response:
            data = json.loads(response.read().decode('utf-8'))
        
        if data.get('status') == 'ok' and data.get('data', {}).get('movies'):
            movie = data['data']['movies'][0]
            poster = movie.get('medium_cover_image') or movie.get('large_cover_image')
            if poster:
                _poster_cache[cache_key] = poster
                return poster
    except Exception:
        pass  # Silently fail - poster is optional
    
    _poster_cache[cache_key] = None
    return None

def fetch_jackett(url, api_key, query, limit=50):
    """
    Fetch torrents from Jackett API
    Endpoint: {url}/api/v2.0/indexers/all/results?apikey={key}&Query={query}
    """
    try:
        params = urllib.parse.urlencode({
            'apikey': api_key,
            'Query': query,
            'Category': '',
            'Tracker': ''
        })
        
        full_url = f"{url.rstrip('/')}/api/v2.0/indexers/all/results?{params}"
        
        req = urllib.request.Request(full_url, headers={
            'User-Agent': 'Termflix/1.0'
        })
        
        with urllib.request.urlopen(req, timeout=15) as response:
            data = json.loads(response.read().decode('utf-8'))
        
        results = []
        if 'Results' in data:
            for item in data['Results'][:limit]:
                result = {
                    'title': item.get('Title', 'Unknown'),
                    'magnet': item.get('MagnetUri', ''),
                    'size': format_size(item.get('Size', 0)),
                    'seeders': item.get('Seeders', 0),
                    'leechers': item.get('Peers', 0),
                    'tracker': item.get('Tracker', 'Unknown'),
                    'poster': None
                }
                
                if result['magnet']:
                    results.append(result)
        
        return results
    
    except Exception as e:
        print(f"Jackett error: {e}", file=sys.stderr)
        return []

def fetch_prowlarr(url, api_key, query, limit=50):
    """
    Fetch torrents from Prowlarr API
    Endpoint: {url}/api/v1/search?apikey={key}&query={query}
    """
    try:
        # Special handling for wildcard query
        if query == '*' or query == '':
            full_url = f"{url.rstrip('/')}/api/v1/search?apikey={api_key}&query=*"
        else:
            params = urllib.parse.urlencode({
                'apikey': api_key,
                'query': query
            })
            full_url = f"{url.rstrip('/')}/api/v1/search?{params}"
        
        if os.environ.get('TORRENT_DEBUG'):
            print(f"DEBUG: Fetching from Prowlarr: {full_url}", file=sys.stderr)
        
        req = urllib.request.Request(full_url, headers={
            'User-Agent': 'Termflix/1.0',
            'X-Api-Key': api_key
        })
        
        with urllib.request.urlopen(req, timeout=15) as response:
            data = json.loads(response.read().decode('utf-8'))
        
        if not data:
            return []

        if os.environ.get('TORRENT_DEBUG'):
            print(f"DEBUG: Got {len(data)} results from Prowlarr", file=sys.stderr)

        results = []
        for item in data[:limit]:
            title = item.get('title', 'Unknown')
            
            # Get magnet/download URL
            magnet = item.get('magnetUrl', '') or item.get('downloadUrl', '')
            if not magnet:
                guid = item.get('guid', '')
                if guid.startswith('magnet:'):
                    magnet = guid
                elif guid.startswith('http'):
                    magnet = guid
            
            if not magnet:
                continue
            
            result = {
                'title': title,
                'magnet': magnet,
                'size': format_size(item.get('size', 0)),
                'seeders': item.get('seeders', 0),
                'leechers': item.get('leechers', 0),
                'tracker': item.get('indexer', 'Unknown'),
                'poster': None
            }
            results.append(result)
        
        return results
    
    except urllib.error.HTTPError as e:
        print(f"Prowlarr HTTP error {e.code}: {e.reason}", file=sys.stderr)
        return []
    except urllib.error.URLError as e:
        print(f"Prowlarr URL error: {e.reason}", file=sys.stderr)
        return []
    except Exception as e:
        print(f"Prowlarr error: {e}", file=sys.stderr)
        return []

def enrich_with_posters(results, max_workers=5):
    """Fetch posters for results in parallel (limited to avoid slowdown)"""
    # Only fetch posters for first N items to avoid slowdown
    items_to_enrich = results[:20]
    
    def fetch_poster_for_result(result):
        name, year = extract_movie_info(result['title'])
        poster = fetch_yts_poster(name, year)
        result['poster'] = poster
        return result
    
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(fetch_poster_for_result, r): r for r in items_to_enrich}
        for future in as_completed(futures, timeout=10):
            try:
                future.result()
            except Exception:
                pass
    
    return results

def format_size(size_bytes):
    """Convert bytes to human-readable format"""
    if not size_bytes or size_bytes == 0:
        return 'N/A'
    
    size_bytes = int(size_bytes)
    
    if size_bytes < 1024:
        return f"{size_bytes}B"
    elif size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.2f}KB"
    elif size_bytes < 1024 * 1024 * 1024:
        return f"{size_bytes / 1024 / 1024:.2f}MB"
    else:
        return f"{size_bytes / 1024 / 1024 / 1024:.2f}GB"

def main():
    """Main CLI interface"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Jackett/Prowlarr Torrent Search')
    parser.add_argument('query', help='Search query (* for all)')
    parser.add_argument('--type', choices=['jackett', 'prowlarr'], default='jackett', help='API type')
    parser.add_argument('--url', required=True, help='Jackett/Prowlarr URL')
    parser.add_argument('--api-key', required=True, help='API key')
    parser.add_argument('--limit', type=int, default=50, help='Max results')
    parser.add_argument('--no-posters', action='store_true', help='Skip poster fetching')
    
    args = parser.parse_args()
    
    # Fetch results
    if args.type == 'jackett':
        results = fetch_jackett(args.url, args.api_key, args.query, args.limit)
    else:
        results = fetch_prowlarr(args.url, args.api_key, args.query, args.limit)
    
    # Enrich with posters (unless disabled)
    if results and not args.no_posters:
        results = enrich_with_posters(results)
    
    # Output in termflix format: SOURCE|NAME|MAGNET|QUALITY(seeds)|SIZE|EXTRA|POSTER
    # group_results.py extracts seeds from quality field (field 3)
    for result in results:
        # Skip results with no seeds
        seeds = result['seeders']
        if not seeds:
            continue
        try:
            seed_count = int(seeds)
            if seed_count == 0:
                continue
        except (ValueError, TypeError):
            # If we can't convert to int, assume it has seeds
            pass

        source = result['tracker']
        title = result['title'].replace('|', ' ')
        poster = result.get('poster') or 'N/A'
        quality_with_seeds = f"{seeds} seeds"

        # Truncate very long URLs/magnet links to prevent FZF display issues
        magnet = result['magnet']
        if len(magnet) > 500:
            magnet = magnet[:500] + "..."

        print(f"{source}|{title}|{magnet}|unknown|{seeds}|{result['size']}|N/A|{poster}")
    
    return 0 if results else 1

if __name__ == '__main__':
    sys.exit(main())