#!/usr/bin/env python3
"""
Termflix - 1337x Torrent Search
Searches 1337x.to for torrents by keyword.
Input: Search query via environment variable SEARCH_QUERY
Output: Pipe-delimited results to stdout
"""
import sys
import os
import re
import urllib.parse
import urllib.request


def search_1337x(query):
    """Search 1337x.to for torrents."""
    if not query:
        return
    
    # URL encode the query
    encoded_query = urllib.parse.quote_plus(query)
    search_url = f"https://1337x.to/search/{encoded_query}/1/"
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
    }
    
    try:
        req = urllib.request.Request(search_url, headers=headers)
        with urllib.request.urlopen(req, timeout=5) as response:
            html = response.read().decode('utf-8', errors='ignore')
            
            # Extract torrent links and names
            # Pattern: <a href="/torrent/ID/NAME">DISPLAY_NAME</a>
            pattern = r'<a href="/torrent/([^"]+)">([^<]+)</a>'
            matches = re.findall(pattern, html)
            
            count = 0
            for torrent_path, name in matches:
                # Skip if it's not an actual torrent link
                if '/' not in torrent_path or torrent_path == 'href':
                    continue
                
                # Extract ID from path (format: ID/torrent-name)
                parts = torrent_path.split('/')
                if len(parts) >= 1:
                    torrent_id = parts[0]
                    
                    # Output format: Source|Name|URL|Quality|Size
                    print(f"1337x|{name.strip()}|https://1337x.to/torrent/{torrent_path}|N/A|N/A", flush=True)
                    
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
    
    search_1337x(query)
