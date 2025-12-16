#!/usr/bin/env python3
"""
Termflix - Poster Fetcher
Fetches movie poster URL with fallback chain:
1. OMDb (API Key - best for title search)
2. YTS (Public API - Movies only)
3. TMDB (API Key)
4. Google Images (Scrape)

OPTIMIZED: Pre-compiled regex, parallel fallback with ThreadPoolExecutor
"""
import sys
import os
import json
import urllib.request
import urllib.parse
import re
import ssl
import html
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

# Pre-compiled regex patterns
_CLEAN_TITLE_RE = re.compile(r'\(\d{4}\)')
_QUALITY_STRIP_RE = re.compile(r'(1080p|720p|WEB-DL|BluRay|HDRip|x265|HEVC).*', re.IGNORECASE)
_JPG_URL_RE = re.compile(r'(https?://[^"]+?\.jpg)')
_JPEG_URL_RE = re.compile(r'(https?://[^"]+?\.jpeg)')
_IMG_SRC_RE = re.compile(r'<img[^>]+src=["\']?(https?://[^"\'>\s]+)')

# Shared SSL context
_SSL_CTX = ssl.create_default_context()
_SSL_CTX.check_hostname = False
_SSL_CTX.verify_mode = ssl.CERT_NONE

# Load API keys from config file
_config = {}
def load_config():
    global _config
    if _config:
        return _config
    
    config_path = Path.home() / ".config" / "termflix" / "config"
    if config_path.exists():
        try:
            with open(config_path) as f:
                for line in f:
                    line = line.strip()
                    if '=' in line and not line.startswith('#'):
                        key, value = line.split('=', 1)
                        _config[key.strip()] = value.strip().strip('"\'')
        except Exception:
            pass
    return _config


def get_api_key(name):
    """Get API key from config file or environment variable"""
    config = load_config()
    return config.get(name) or os.environ.get(name)


def clean_title_and_year(title):
    """Clean title and extract year for API search"""
    year = None
    
    # Extract year if present (19xx or 20xx)
    year_match = re.search(r'\(?((?:19|20)\d{2})\)?', title)
    if year_match:
        year = year_match.group(1)
        
    # Clean title
    clean = _CLEAN_TITLE_RE.sub('', title)
    clean = _QUALITY_STRIP_RE.sub('', clean)
    clean = clean.replace('.', ' ').strip()
    
    # Remove year from title if it was part of it to get clean name
    if year:
        clean = clean.replace(year, '').replace('()', '').strip()
        
    return clean, year


def fetch_omdb(query, year, api_key):
    """Fetch poster from OMDb"""
    try:
        url = f"http://www.omdbapi.com/?apikey={api_key}&t={urllib.parse.quote(query)}"
        if year:
            url += f"&y={year}"
            
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=3) as response:
            data = json.loads(response.read().decode())
            if data.get('Response') == 'True' and data.get('Poster') and data['Poster'] != 'N/A':
                return data['Poster']
    except Exception:
        pass
    return None


def fetch_yts(query):
    """Fetch poster from YTS (YTS API doesn't support year filtering well in query_term)"""
    try:
        url = f"https://yts.mx/api/v2/list_movies.json?query_term={urllib.parse.quote(query)}&limit=1"
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())
            if data.get('status') == 'ok' and data['data'].get('movie_count', 0) > 0:
                movie = data['data']['movies'][0]
                return movie.get('medium_cover_image') or movie.get('large_cover_image')
    except Exception:
        pass
    return None


def fetch_tmdb(query, year, api_key):
    """Fetch poster from TMDB"""
    try:
        url = f"https://api.themoviedb.org/3/search/multi?api_key={api_key}&query={urllib.parse.quote(query)}&page=1"
        if year:
            url += f"&year={year}"
            
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=3) as response:
            data = json.loads(response.read().decode())
            if data.get('results'):
                for res in data['results']:
                    if res.get('poster_path'):
                        # Basic year check if we have one, to reduce false positives
                        if year:
                            release_date = res.get('release_date') or res.get('first_air_date') or ''
                            if year not in release_date:
                                continue
                        return f"https://image.tmdb.org/t/p/w500{res['poster_path']}"
                
                # If we filtered too aggressively and found nothing, try returning first result
                if year and data.get('results'):
                     if data['results'][0].get('poster_path'):
                        return f"https://image.tmdb.org/t/p/w500{data['results'][0]['poster_path']}"
                        
    except Exception:
        pass
    return None


def fetch_google(query, year=None):
    """Fetch poster from Google Images (last resort)"""
    try:
        search_query = f"{query} movie poster"
        if year:
            search_query = f"{query} {year} movie poster"
            
        url = f"https://www.google.com/search?q={urllib.parse.quote(search_query)}&tbm=isch"
        
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        }
        
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, context=_SSL_CTX, timeout=10) as response:
            html_content = response.read().decode('utf-8', errors='ignore')
            
        urls = _JPG_URL_RE.findall(html_content)
        
        # Also look for img src tags directly (catch thumbnails)
        img_srcs = _IMG_SRC_RE.findall(html_content)
        urls.extend(img_srcs)
        
        # Filter URLs
        high_quality = []
        thumbnails = []
        
        for u in urls:
            if 'logo' in u or 'favicon' in u:
                continue
                
            if 'gstatic' in u:
                thumbnails.append(u)
            elif 'google' not in u:
                high_quality.append(u)
        
        # print(f"DEBUG: Found {len(high_quality)} HQ images and {len(thumbnails)} thumbnails", file=sys.stderr)
        
        if high_quality:
            return html.unescape(high_quality[0])
            
        if thumbnails:
            return html.unescape(thumbnails[0])
            
    except Exception:
        pass
    return None


def main():
    if len(sys.argv) < 2:
        return

    raw_query = sys.argv[1]
    query, year = clean_title_and_year(raw_query)
    
    omdb_key = get_api_key('OMDB_API_KEY')
    tmdb_key = get_api_key('TMDB_API_KEY')
    
    # OPTIMIZATION: Try APIs in parallel
    # Only Google is excluded from parallel (it's a fallback)
    with ThreadPoolExecutor(max_workers=3) as executor:
        futures = {}
        
        if omdb_key:
            futures[executor.submit(fetch_omdb, query, year, omdb_key)] = 'omdb'
        
        # YTS works best with the exact original search term from the tracker usually
        futures[executor.submit(fetch_yts, raw_query)] = 'yts'
        
        if tmdb_key:
            futures[executor.submit(fetch_tmdb, query, year, tmdb_key)] = 'tmdb'
        
        # Return first successful result
        for future in as_completed(futures):
            try:
                result = future.result()
                if result:
                    print(result)
                    return
            except Exception:
                pass
    
    # Fallback to Google (slower, so done separately)
    poster = fetch_google(query, year)
    if poster:
        print(poster)
        return
    
    print("null")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
