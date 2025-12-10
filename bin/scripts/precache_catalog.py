#!/usr/bin/env python3
"""
Termflix - Pre-cache Catalog Data
Runs in background to pre-fetch posters and descriptions for first N movies.
"""
import sys
import os
import json
import hashlib
import urllib.request
from pathlib import Path

# Cache directories
CACHE_DIR = Path.home() / ".cache" / "termflix"
POSTER_CACHE = CACHE_DIR / "posters"
DESC_CACHE = CACHE_DIR / "descriptions"
POSTER_URL_CACHE = CACHE_DIR / "poster_urls"

# API keys from environment
OMDB_API_KEY = os.environ.get("OMDB_API_KEY", "")
TMDB_API_KEY = os.environ.get("TMDB_API_KEY", "")

def ensure_dirs():
    """Create cache directories if they don't exist."""
    POSTER_CACHE.mkdir(parents=True, exist_ok=True)
    DESC_CACHE.mkdir(parents=True, exist_ok=True)
    POSTER_URL_CACHE.mkdir(parents=True, exist_ok=True)

def get_hash(text):
    """Get MD5 hash of text."""
    return hashlib.md5(text.encode()).hexdigest()

def fetch_json(url, timeout=10):
    """Fetch JSON from URL."""
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception:
        return None

def fetch_poster_url(title):
    """Fetch poster URL for a movie title."""
    # Try TMDB first (more reliable)
    if TMDB_API_KEY:
        url = f"https://api.themoviedb.org/3/search/movie?api_key={TMDB_API_KEY}&query={urllib.parse.quote(title)}"
        data = fetch_json(url, timeout=5)
        if data and data.get('results'):
            poster_path = data['results'][0].get('poster_path')
            if poster_path:
                return f"https://image.tmdb.org/t/p/w500{poster_path}"
    
    # Try YTS as fallback
    clean_title = title.split('(')[0].strip()
    url = f"https://yts.mx/api/v2/list_movies.json?query_term={urllib.parse.quote(clean_title)}&limit=1"
    data = fetch_json(url, timeout=5)
    if data and data.get('data', {}).get('movies'):
        return data['data']['movies'][0].get('medium_cover_image', '')
    
    return None

def fetch_description(title):
    """Fetch movie description."""
    # Try OMDB
    if OMDB_API_KEY:
        url = f"http://www.omdbapi.com/?apikey={OMDB_API_KEY}&t={urllib.parse.quote(title)}"
        data = fetch_json(url, timeout=5)
        if data and data.get('Response') == 'True':
            return data.get('Plot', '')
    
    # Try TMDB
    if TMDB_API_KEY:
        url = f"https://api.themoviedb.org/3/search/movie?api_key={TMDB_API_KEY}&query={urllib.parse.quote(title)}"
        data = fetch_json(url, timeout=5)
        if data and data.get('results'):
            return data['results'][0].get('overview', '')
    
    return ""

def download_poster(url, dest_path):
    """Download poster and save as PNG."""
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=10) as response:
            with open(dest_path, 'wb') as f:
                f.write(response.read())
        return True
    except Exception:
        return False

def precache_movie(title, poster_url=None):
    """Pre-cache poster and description for a movie."""
    title_hash = get_hash(title.lower())
    
    # Cache description
    desc_file = DESC_CACHE / f"{title_hash}.txt"
    if not desc_file.exists():
        desc = fetch_description(title)
        if desc:
            desc_file.write_text(desc)
    
    # Get poster URL if not provided
    if not poster_url or poster_url in ('N/A', 'null', ''):
        url_cache = POSTER_URL_CACHE / f"{title_hash}.txt"
        if url_cache.exists():
            poster_url = url_cache.read_text().strip()
        else:
            poster_url = fetch_poster_url(title)
            if poster_url:
                url_cache.write_text(poster_url)
    
    # Download poster
    if poster_url and poster_url not in ('N/A', 'null', ''):
        url_hash = get_hash(poster_url)
        poster_file = POSTER_CACHE / f"{url_hash}.png"
        if not poster_file.exists():
            # Download to temp then move
            temp_file = POSTER_CACHE / f"{url_hash}.tmp"
            if download_poster(poster_url, temp_file):
                # Convert to PNG using sips if available (macOS)
                import subprocess
                try:
                    subprocess.run(['sips', '-s', 'format', 'png', '--resampleWidth', '400',
                                    str(temp_file), '--out', str(poster_file)],
                                   capture_output=True, timeout=10)
                    temp_file.unlink(missing_ok=True)
                except Exception:
                    # Just rename if sips fails
                    temp_file.rename(poster_file)

def main():
    """Main function - read catalog from stdin and precache."""
    ensure_dirs()
    
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 50
    count = 0
    
    # Read COMBINED format from stdin: COMBINED|Name|Sources|Qualities|Seeds|Sizes|Magnets|Poster|...
    for line in sys.stdin:
        line = line.strip()
        if not line or '|' not in line:
            continue
        
        parts = line.split('|')
        if len(parts) < 2:
            continue
        
        # Extract title and poster
        title = parts[1] if parts[0] == 'COMBINED' else parts[1]
        poster_url = parts[7] if len(parts) > 7 else None
        
        # Pre-cache this movie
        try:
            precache_movie(title, poster_url)
            count += 1
            print(f"Cached: {title}", file=sys.stderr)
        except Exception as e:
            print(f"Error caching {title}: {e}", file=sys.stderr)
        
        if count >= limit:
            break
    
    print(f"Pre-cached {count} movies", file=sys.stderr)

if __name__ == "__main__":
    import urllib.parse
    main()
