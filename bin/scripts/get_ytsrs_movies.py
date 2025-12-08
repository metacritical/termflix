#!/usr/bin/env python3
"""
Termflix - YTSRS Movies Browser
Browses and fetches movies from YTS JSON API for catalog display.
Input: sort, limit, page, genre as command line arguments
Output: Pipe-delimited torrent results to stdout
"""
import sys
import json
import urllib.parse
import urllib.request
import ssl


def scrape_yts_movies(sort='date_added', limit=20, page=1, genre=None):
    """Fetch movies from YTS JSON API - more reliable than HTML scraping."""
    # YTS API domains in order of reliability
    domains = [
        'https://yts.lt',
        'https://yts.mx', 
        'https://yts.rs',
        'https://yts.torrentbay.to'
    ]
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
    }
    
    # Create SSL context that ignores certificate errors
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    
    # Map sort parameter to API format
    sort_map = {
        'seeds': 'seeds',
        'date_added': 'date_added',
        'year': 'year',
        'rating': 'rating',
        'likes': 'like_count',
        'downloads': 'download_count'
    }
    api_sort = sort_map.get(sort, 'date_added')
    
    for domain in domains:
        try:
            # Build API URL
            url = f"{domain}/api/v2/list_movies.json"
            params = {
                'limit': limit,
                'page': page,
                'sort_by': api_sort,
                'order_by': 'desc'
            }
            if genre:
                params['genre'] = genre
            
            url += '?' + urllib.parse.urlencode(params)
            
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, context=ctx, timeout=12) as response:
                if response.status != 200:
                    continue
                    
                data = json.loads(response.read().decode('utf-8', errors='ignore'))
                
                if data.get('status') != 'ok':
                    continue
                
                movies = data.get('data', {}).get('movies', [])
                if not movies:
                    continue
                
                # Process each movie
                for movie in movies:
                    try:
                        title = movie.get('title', 'Unknown')
                        year = movie.get('year')
                        poster = movie.get('medium_cover_image', 'N/A')
                        
                        # Get torrents - prefer 1080p, fallback to 720p
                        torrents = movie.get('torrents', [])
                        if not torrents:
                            continue
                        
                        # Find best torrent (1080p > 720p > any)
                        best_torrent = None
                        for t in torrents:
                            quality = t.get('quality', '')
                            if quality == '1080p':
                                best_torrent = t
                                break
                            elif quality == '720p' and not best_torrent:
                                best_torrent = t
                            elif not best_torrent:
                                best_torrent = t
                        
                        if not best_torrent:
                            continue
                        
                        hash_val = best_torrent.get('hash', '')
                        if not hash_val:
                            continue
                            
                        quality = best_torrent.get('quality', '1080p')
                        size = best_torrent.get('size', 'N/A')
                        seeds = best_torrent.get('seeds', 0)
                        
                        year_str = f" ({year})" if year else ""
                        extra = f"{seeds} seeds"
                        
                        # Build magnet link
                        magnet = f"magnet:?xt=urn:btih:{hash_val}"
                        
                        print(f"YTS|{title}{year_str}|{magnet}|{quality}|{size}|{extra}|{poster}", flush=True)
                        
                    except Exception:
                        continue
                
                # If we got here successfully, we're done
                return
                
        except Exception:
            continue


if __name__ == '__main__':
    sort = sys.argv[1] if len(sys.argv) > 1 else 'date_added'
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    page = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    genre = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] != "" else None
    
    scrape_yts_movies(sort=sort, limit=limit, page=page, genre=genre)
