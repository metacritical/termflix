#!/usr/bin/env python3
"""
Termflix - Poster Fetcher
Fetches movie poster URL with fallback chain:
1. TMDB (API Key)
2. YTS (Public API - Movies only)
3. OMDb (API Key)
4. Google Images (Scrape)
"""
import sys
import os
import json
import urllib.request
import urllib.parse
import re
import ssl

def clean_title(title):
    # Remove year (1999) for better search
    # But keep it for verification if needed? 
    # Search usually works better with just title on APIs
    clean = re.sub(r'\(\d{4}\)', '', title)
    clean = re.sub(r'(1080p|720p|WEB-DL|BluRay|HDRip|x265|HEVC).*', '', clean, flags=re.IGNORECASE)
    # Remove dots and extra spaces
    clean = clean.replace('.', ' ').strip()
    return clean

def fetch_tmdb(query, api_key):
    try:
        url = f"https://api.themoviedb.org/3/search/multi?api_key={api_key}&query={urllib.parse.quote(query)}&page=1"
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=3) as response:
            data = json.loads(response.read().decode())
            if data.get('results'):
                for res in data['results']:
                    if res.get('poster_path'):
                        return f"https://image.tmdb.org/t/p/w500{res['poster_path']}"
    except Exception:
        pass
    return None

def fetch_yts(query):
    try:
        # YTS is strictly movies
        url = f"https://yts.mx/api/v2/list_movies.json?query_term={urllib.parse.quote(query)}&limit=1"
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=3) as response:
            data = json.loads(response.read().decode())
            if data.get('status') == 'ok' and data['data'].get('movie_count', 0) > 0:
                movie = data['data']['movies'][0]
                return movie.get('medium_cover_image') or movie.get('large_cover_image')
    except Exception:
        pass
    return None

def fetch_omdb(query, api_key):
    try:
        # OMDb search
        url = f"http://www.omdbapi.com/?apikey={api_key}&t={urllib.parse.quote(query)}"
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=3) as response:
            data = json.loads(response.read().decode())
            if data.get('Response') == 'True' and data.get('Poster') and data['Poster'] != 'N/A':
                return data['Poster']
    except Exception:
        pass
    return None

def fetch_google(query):
    try:
        # Simple Google Image scraper
        search_query = f"{query} movie poster"
        url = f"https://www.google.com/search?q={urllib.parse.quote(search_query)}&tbm=isch"
        
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        }
        
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, context=ctx, timeout=4) as response:
            html = response.read().decode('utf-8', errors='ignore')
            
        # Regex for image URLs (simple attempt)
        # Look for http/https image URLs ending in jpg/png/jpeg inside common tags
        # Note: Google changes classes often, relying on img src is safer but thumbnails are small.
        # This regex looks for large image urls in script tags often found in google-images
        urls = re.findall(r'(https?://[^"]+?\.jpg)', html)
        
        valid_urls = [u for u in urls if 'google' not in u and 'gstatic' not in u and 'logo' not in u]
        
        if valid_urls:
            return valid_urls[0]
            
    except Exception:
        pass
    return None

def main():
    if len(sys.argv) < 2:
        return

    raw_query = sys.argv[1]
    query = clean_title(raw_query)
    
    # 1. TMDB
    tmdb_key = os.environ.get('TMDB_API_KEY')
    if tmdb_key:
        poster = fetch_tmdb(query, tmdb_key)
        if poster:
            print(poster)
            return

    # 2. YTS (Movies only, but public and fast)
    poster = fetch_yts(query)
    if poster:
        print(poster)
        return

    # 3. OMDb
    omdb_key = os.environ.get('OMDB_API_KEY')
    if omdb_key:
        poster = fetch_omdb(query, omdb_key)
        if poster:
            print(poster)
            return
            
    # 4. Google Images (Scrape)
    poster = fetch_google(query)
    if poster:
        print(poster)
        return
    
    # Explicitly print null if nothing found, to be handled by bash
    print("null")

if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
