#!/usr/bin/env python3
"""
Termflix - ThePirateBay Torrent Search
Searches ThePirateBay via apibay.org API.
Input: Search query via environment variable SEARCH_QUERY or command line arg
Output: Pipe-delimited results to stdout
"""
import sys
import os
import json
import urllib.parse
import urllib.request


def search_tpb(query):
    """Search ThePirateBay API for torrents."""
    if not query:
        return
    
    # URL encode the query
    encoded_query = urllib.parse.quote(query)
    api_url = f"https://apibay.org/q.php?q={encoded_query}&cat=0"
    
    try:
        req = urllib.request.Request(api_url)
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode('utf-8'))
            
            count = 0
            for item in data:
                # Check if valid result
                info_hash = item.get('info_hash')
                if not info_hash or info_hash == '0000000000000000000000000000000000000000':
                    continue
                
                name = item.get('name', 'Unknown')
                seeders = item.get('seeders', 0)
                size_bytes = item.get('size', 0)
                
                # Convert size to MB
                try:
                    size_mb = int(size_bytes) // (1024 * 1024)
                except:
                    size_mb = 0
                
                # Build magnet link
                magnet = f"magnet:?xt=urn:btih:{info_hash}"
                
                # Output format: Source|Name|Magnet|Qua​lity/Seeds|Size
                print(f"TPB|{name}|{magnet}|{seeders} seeds|{size_mb}MB", flush=True)
                
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
    
    search_tpb(query)
