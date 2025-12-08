#!/usr/bin/env python3
"""
Termflix - EZTV TV Show Search
Searches EZTV for TV show torrents.
Input: Search query via environment variable SEARCH_QUERY or command line arg
Output: Pipe-delimited results to stdout
"""
import sys
import os
import json
import urllib.parse
import urllib.request


def search_eztv(query):
    """Search EZTV API for TV show torrents."""
    if not query:
        return
    
    # URL encode the query
    encoded_query = urllib.parse.quote_plus(query)
    api_url = f"https://eztv.re/api/get-torrents?imdb_id=&limit=20&page=1&query_string={encoded_query}"
    
    try:
        req = urllib.request.Request(api_url)
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode('utf-8'))
            
            torrents_count = data.get('torrents_count', 0)
            if torrents_count == 0:
                return
            
            torrents = data.get('torrents', [])
            
            count = 0
            for torrent in torrents:
                magnet = torrent.get('magnet_url')
                if not magnet:
                    continue
                
                title = torrent.get('title', 'Unknown')
                seeds = torrent.get('seeds', 0)
                size_bytes = torrent.get('size_bytes', 0)
                
                # Convert size to MB
                try:
                    size_mb = int(size_bytes) // (1024 * 1024)
                except:
                    size_mb = 0
                
                # Output format: Source|Name|Magnet|Quality/Seeds|Size
                print(f"EZTV|{title}|{magnet}|{seeds} seeds|{size_mb}MB", flush=True)
                
                count += 1
                if count >= 10:
                    break
                    
    except Exception as e:
        # Silently fail - search continues with other sources
        pass


if __name__ == '__main__':
    query = os.environ.get('SEARCH_QUERY', '')
    if not query and len(sys.argv) > 1:
        query = sys.argv[1]
    
    search_eztv(query)
