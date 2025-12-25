#!/usr/bin/env python3
"""
YouTube Trailer Link Fetcher for Termflix
Searches for movie/show trailers and returns YouTube links.

Usage:
    python3 fetch_trailers.py "Movie Name (2024)"
    python3 fetch_trailers.py "Movie Name" --limit 3
"""

import sys
import re
import urllib.request
import urllib.parse

USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15'


def search_youtube_trailers(query: str, limit: int = 3) -> list[dict]:
    """
    Search YouTube for trailers and return video links.
    Returns list of {title, url, duration} dicts.
    """
    search_url = f"https://www.youtube.com/results?search_query={urllib.parse.quote(query)}"
    
    headers = {
        'User-Agent': USER_AGENT,
        'Accept-Language': 'en-US,en;q=0.9',
    }
    
    try:
        request = urllib.request.Request(search_url, headers=headers)
        with urllib.request.urlopen(request, timeout=10) as response:
            html = response.read().decode('utf-8', errors='ignore')
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return []
    
    results = []
    
    # Pattern to find video IDs and titles in YouTube's initial data
    # YouTube embeds video data in JSON format
    video_pattern = r'"videoId":"([a-zA-Z0-9_-]{11})".*?"title":\{"runs":\[\{"text":"([^"]+)"\}'
    matches = re.findall(video_pattern, html)
    
    seen_ids = set()
    for video_id, title in matches:
        if video_id in seen_ids:
            continue
        seen_ids.add(video_id)
        
        # Skip YouTube Shorts and music
        if 'shorts' in title.lower():
            continue
            
        results.append({
            'title': title,
            'url': f'https://www.youtube.com/watch?v={video_id}',
            'video_id': video_id
        })
        
        if len(results) >= limit:
            break
    
    # Fallback: simpler pattern
    if not results:
        simple_pattern = r'/watch\?v=([a-zA-Z0-9_-]{11})'
        video_ids = re.findall(simple_pattern, html)
        for vid in video_ids[:limit]:
            if vid not in seen_ids:
                results.append({
                    'title': 'Trailer',
                    'url': f'https://www.youtube.com/watch?v={vid}',
                    'video_id': vid
                })
                seen_ids.add(vid)
    
    return results


def main():
    if len(sys.argv) < 2:
        print("Usage: fetch_trailers.py 'Movie Name (Year)' [--limit N]", file=sys.stderr)
        sys.exit(1)
    
    title = sys.argv[1]
    limit = 3
    
    if '--limit' in sys.argv:
        idx = sys.argv.index('--limit')
        if idx + 1 < len(sys.argv):
            try:
                limit = int(sys.argv[idx + 1])
            except ValueError:
                pass
    
    # Clean title for search
    clean_title = re.sub(r'\s*\(([12][0-9]{3})\)\s*', r' \1 ', title).strip()
    query = f"{clean_title} official trailer"
    
    results = search_youtube_trailers(query, limit)
    
    if not results:
        print("No trailers found", file=sys.stderr)
        sys.exit(1)
    
    # Output format: title|url (one per line)
    for r in results:
        print(f"{r['title']}|{r['url']}")


if __name__ == '__main__':
    main()
