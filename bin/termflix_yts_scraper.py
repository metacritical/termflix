#!/usr/bin/env python3
"""
YTS Website Scraper - Alternative to unreliable API
Scrapes yts.mx website directly to get movie data
"""

import sys
import re
import json
import urllib.parse
import urllib.request
import os

def scrape_yts_movies(sort='date_added', order='desc', limit=20, page=1, genre=None, quality='1080p', keyword=None):
    """Scrape movies from YTS website - uses working domains: yts.rs and yts.hn"""
    # Try multiple YTS domains in order of preference (yts.mx is not working)
    # User confirmed these work: https://yts.rs/browse-movies, https://yts.hn/browse-movies
    # Try multiple YTS domains in order of preference
    # yts.mx is the official one, but others are reliable mirrors if it's blocked
    domains = [
        'https://yts.mx', 
        'https://yts.ag', 
        'https://yts.am', 
        'https://yts.pm', 
        'https://yts.lt',
        'https://yts.rs', 
        'https://yts.hn'
    ]
    base_url = None
    
    # Test which domain works by checking browse-movies page
    for domain in domains:
        try:
            test_url = f"{domain}/browse-movies"
            req = urllib.request.Request(test_url, headers={
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.9'
            })
            with urllib.request.urlopen(req, timeout=10) as response:
                html = response.read().decode('utf-8', errors='ignore')
                # Check if we got actual HTML content (not error page)
                if response.status == 200 and len(html) > 1000 and 'movie' in html.lower():
                    base_url = domain
                    break
        except Exception as e:
            continue
    
    if not base_url:
        # If both fail, default to yts.rs (most reliable)
        base_url = 'https://yts.rs'
    
    # Build browse URL
    url = f"{base_url}/browse-movies"
    params = []
    if sort:
        params.append(f"sort_by={sort}")
    if order:
        params.append(f"order_by={order}")
    if page > 1:
        params.append(f"page={page}")
    if genre:
        params.append(f"genre={urllib.parse.quote(genre)}")
    if keyword:
        params.append(f"keyword={urllib.parse.quote(keyword)}")
    
    if params:
        url += "?" + "&".join(params)
    
    try:
        req = urllib.request.Request(url, headers={
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9'
        })
        
        with urllib.request.urlopen(req, timeout=15) as response:
            html = response.read().decode('utf-8', errors='ignore')
    except Exception as e:
        if os.environ.get('YTS_SCRAPER_DEBUG'):
            print(f"Error fetching browse page: {e}", file=sys.stderr)
        return []
    
    if not html or len(html) < 1000:
        return []
    
    results = []
    count = 0
    
    # Find movie links - YTS uses /movies/[slug] pattern
    movie_link_pattern = r'<a[^>]+href="/movies/([^"]+)"[^>]*class="[^"]*browse-movie-link[^"]*"[^>]*>'
    movie_links = re.findall(movie_link_pattern, html)
    
    # Alternative pattern if first doesn't match
    if not movie_links:
        movie_link_pattern = r'<a[^>]+href="/movies/([^"]+)"[^>]*>'
        movie_links = re.findall(movie_link_pattern, html)
    
    if not movie_links:
        return []
    
    # Process each movie
    for slug in movie_links[:limit]:
        if count >= limit:
            break
        
        try:
            # Use the working base_url we found earlier
            movie_url = f"{base_url}/movies/{slug}"
            req = urllib.request.Request(movie_url, headers={
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
                'Accept': 'text/html,application/xhtml+xml'
            })
            
            with urllib.request.urlopen(req, timeout=10) as response:
                movie_html = response.read().decode('utf-8', errors='ignore')
            
            if not movie_html or len(movie_html) < 500:
                continue
            
            # Extract title
            title_match = re.search(r'<h1[^>]*>([^<]+)</h1>', movie_html)
            if not title_match:
                continue
            title = title_match.group(1).strip()
            
            # Extract year
            year_match = re.search(r'<span[^>]*class="[^"]*year[^"]*"[^>]*>(\d{4})</span>', movie_html)
            year = year_match.group(1) if year_match else None
            
            # Extract poster
            poster_match = re.search(r'<img[^>]+class="[^"]*movie-poster[^"]*"[^>]+src="([^"]+)"', movie_html)
            poster = 'N/A'
            if poster_match:
                poster = poster_match.group(1)
                if poster.startswith('/'):
                    poster = f"{base_url}{poster}"
            
            # Extract torrent hash - try multiple patterns
            hash_match = re.search(r'magnet:\?xt=urn:btih:([a-fA-F0-9]{40})', movie_html)
            if not hash_match:
                hash_match = re.search(r'data-hash="([a-fA-F0-9]{40})"', movie_html)
            if not hash_match:
                hash_match = re.search(r'hash["\s]*[:=]["\s]*([a-fA-F0-9]{40})', movie_html)
            
            if not hash_match:
                continue
            
            hash_val = hash_match.group(1)
            
            # Extract quality
            quality_match = re.search(r'<span[^>]*class="[^"]*quality[^"]*"[^>]*>([^<]+)</span>', movie_html, re.IGNORECASE)
            movie_quality = quality_match.group(1).strip() if quality_match else quality
            
            # Extract size
            size_match = re.search(r'<span[^>]*class="[^"]*size[^"]*"[^>]*>([^<]+)</span>', movie_html, re.IGNORECASE)
            size = size_match.group(1).strip() if size_match else 'N/A'
            
            # Extract seeds if available
            seeds_match = re.search(r'<span[^>]*class="[^"]*seeds[^"]*"[^>]*>(\d+)</span>', movie_html, re.IGNORECASE)
            seeds = int(seeds_match.group(1)) if seeds_match else 0
            
            # Output in pipe-delimited format
            year_str = f" ({year})" if year else ""
            extra = f"{seeds} seeds" if seeds > 0 else "N/A"
            print(f"YTS|{title}{year_str}|magnet:?xt=urn:btih:{hash_val}|{movie_quality}|{size}|{extra}|{poster}", flush=True)
            count += 1
            
        except Exception as e:
            # Skip on error (silent by default, but can enable debug)
            if os.environ.get('YTS_SCRAPER_DEBUG'):
                print(f"Error processing {slug}: {e}", file=sys.stderr)
            continue
    
    return results

if __name__ == '__main__':
    # Parse command line args
    sort = sys.argv[1] if len(sys.argv) > 1 else 'date_added'
    order = sys.argv[2] if len(sys.argv) > 2 else 'desc'
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else 20
    page = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    genre = sys.argv[5] if len(sys.argv) > 5 else None
    keyword = sys.argv[6] if len(sys.argv) > 6 else None
    
    scrape_yts_movies(sort=sort, order=order, limit=limit, page=page, genre=genre, keyword=keyword)
