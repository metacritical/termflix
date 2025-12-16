#!/usr/bin/env python3
"""
Termflix - Search Extra Torrents
Reads "Title|Year" from stdin, searches TPB for all versions, and outputs raw torrent lines.
Used to find better qualities/sources for movies already identified in the catalog.
"""
import sys
import urllib.request
import urllib.parse
import json
import zlib
import re
from concurrent.futures import ThreadPoolExecutor, as_completed

# API Endpoints
TPB_API = "https://apibay.org/q.php"
TRACKERS = [
    "udp://tracker.coppersurfer.tk:6969/announce",
    "udp://tracker.openbittorrent.com:80/announce",
    "udp://tracker.opentrackr.org:1337/announce",
    "udp://tracker.leechers-paradise.org:6969/announce",
    "udp://tracker.zer0day.to:1337/announce",
    "udp://9.rarbg.to:2710/announce",
    "udp://9.rarbg.me:2780/announce",
    "udp://tracker.internetwarriors.net:1337/announce"
]

def get_trackers_string():
    """Return URL-encoded tracker string."""
    tr_params = []
    for tr in TRACKERS:
        tr_params.append(f"tr={urllib.parse.quote(tr)}")
    return "&".join(tr_params)

TRACKERS_STR = get_trackers_string()

def search_tpb(title, year):
    """Search TPB for 'Title Year' and return formatted lines."""
    # Clean title: remove year parens if present to avoid "Movie (2022) 2022"
    if year:
        title = title.replace(f"({year})", "").strip()
        
    query = f"{title} {year}".strip()
    try:
        params = urllib.parse.urlencode({'q': query, 'cat': '200'}) # 200 = Video
        url = f"{TPB_API}?{params}"
        
        req = urllib.request.Request(url)
        req.add_header('User-Agent', 'Mozilla/5.0')
        
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read())
            
        if not data or data[0].get('name') == 'No results returned':
            return []
            
        results = []
        for item in data:
            name = item.get('name', 'Unknown')
            # Basic validation: Must contain title words and year
            # (Simple check to avoid completely unrelated results)
            if year and year not in name:
                continue
                
            info_hash = item.get('info_hash')
            seeders = item.get('seeders', '0')
            size_bytes = int(item.get('size', 0))
            
            # Convert size
            if size_bytes > 1073741824:
                size = f"{size_bytes/1073741824:.1f}GB"
            else:
                size = f"{size_bytes/1048576:.0f}MB"
            
            # Determine quality
            quality = "Unknown"
            if "2160p" in name or "4K" in name: quality = "4K"
            elif "1080p" in name: quality = "1080p"
            elif "720p" in name: quality = "720p"
            elif "480p" in name: quality = "480p"
            elif "CAM" in name or "HDCAM" in name: quality = "CAM"
            elif "HDRip" in name or "DVDRip" in name: quality = "Rip"
            elif "WEBRip" in name or "WEB-DL" in name: quality = "Web"
            
            # Construct magnet
            magnet = f"magnet:?xt=urn:btih:{info_hash}&dn={urllib.parse.quote(name)}&{TRACKERS_STR}"
            
            # Format: Source|Name|Magnet|Quality|Size|Seeds
            line = f"TPB|{name}|{magnet}|{quality}|{size}|{seeders}"
            results.append(line)
            
        return results
        
    except Exception as e:
        # Silently fail on error
        return []

def worker(line):
    """Worker function to process a single 'Title|Year' line."""
    try:
        parts = line.strip().split('|')
        if len(parts) >= 2:
            title = parts[0]
            year = parts[1]
            return search_tpb(title, year)
    except:
        pass
    return []

def main():
    """Read 'Title|Year' lines from stdin and search in parallel."""
    tasks = []
    # Read all input lines
    for line in sys.stdin:
        line = line.strip()
        if line:
            tasks.append(line)

    results = []
    # Parallel execution (50 workers)
    with ThreadPoolExecutor(max_workers=50) as executor:
        futures = [executor.submit(worker, t) for t in tasks]
        for future in as_completed(futures):
            res = future.result()
            if res:
                results.extend(res)
                
    # Output all found torrents
    for line in results:
        print(line)

if __name__ == "__main__":
    main()
