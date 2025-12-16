#!/usr/bin/env python3
"""
Termflix - Metadata Fetcher
Fetches movie metadata (Year, Runtime, Genre, Rating, Plot) with fallback chain:
1. OMDb (API Key - Best quality)
2. TMDB (API Key - Good quality)
3. YTS (Public API - Good backup for torrent movies)

Output: JSON object normalized to OMDb format.
"""
import sys
import os
import json
import urllib.request
import urllib.parse
import re
import ssl
from pathlib import Path

# Shared SSL context
_SSL_CTX = ssl.create_default_context()
_SSL_CTX.check_hostname = False
_SSL_CTX.verify_mode = ssl.CERT_NONE

# Load API keys from config file
_config = {}
def load_config():
    global _config
    if _config: return _config
    config_path = Path.home() / ".config" / "termflix" / "config"
    if config_path.exists():
        try:
            with open(config_path) as f:
                for line in f:
                    if '=' in line and not line.strip().startswith('#'):
                        key, value = line.split('=', 1)
                        _config[key.strip()] = value.strip().strip('"\'')
        except: pass
    return _config

def get_api_key(name):
    return load_config().get(name) or os.environ.get(name)

def clean_title_and_year(full_input):
    """Parse title and year from input string 'Title (Year)' or just 'Title'"""
    title = full_input
    year = None
    
    # Check for (Year) at end
    match = re.search(r'^(.*?)\s*\((\d{4})\)$', full_input)
    if match:
        title = match.group(1)
        year = match.group(2)
        
    return title, year

def normalize_response(source, data):
    """Normalize distinct API responses to standard OMDb format"""
    res = {
        'Year': '', 'Runtime': '', 'Genre': '', 'imdbRating': '', 'Plot': '',
        'Response': 'True', 'Source': source
    }
    
    if source == 'OMDB':
        return data  # Already standard
        
    elif source == 'TMDB':
        # TMDB returns: release_date, runtime (int), genres (list of dicts), vote_average, overview
        res['Year'] = (data.get('release_date') or '')[:4]
        res['Runtime'] = f"{data.get('runtime', 0)} min" if data.get('runtime') else ''
        res['Genre'] = ", ".join([g['name'] for g in data.get('genres', [])])
        res['imdbRating'] = str(data.get('vote_average', ''))
        res['Plot'] = data.get('overview', '')
        
    elif source == 'YTS':
        # YTS returns: year, runtime (int), genres (list), rating, summary
        movie = data
        res['Year'] = str(movie.get('year', ''))
        res['Runtime'] = f"{movie.get('runtime', 0)} min" if movie.get('runtime') else ''
        res['Genre'] = ", ".join(movie.get('genres') or [])
        res['imdbRating'] = str(movie.get('rating', ''))
        res['Plot'] = movie.get('summary', '') or movie.get('description_full', '')
        
    return res

def fetch_omdb(title, year):
    api_key = get_api_key('OMDB_API_KEY')
    if not api_key: return None
    
    query = {'t': title, 'apikey': api_key}
    if year: query['y'] = year
    
    url = f"http://www.omdbapi.com/?{urllib.parse.urlencode(query)}"
    try:
        with urllib.request.urlopen(url, timeout=5, context=_SSL_CTX) as response:
            data = json.load(response)
            if data.get('Response') == 'True':
                return normalize_response('OMDB', data)
    except: pass
    return None

def fetch_tmdb(title, year):
    api_key = get_api_key('TMDB_API_KEY')
    if not api_key: return None
    
    # 1. Search
    search_url = f"https://api.themoviedb.org/3/search/movie?api_key={api_key}&query={urllib.parse.quote(title)}"
    if year: search_url += f"&year={year}"
    
    try:
        with urllib.request.urlopen(search_url, timeout=5, context=_SSL_CTX) as response:
            search_res = json.load(response)
            if search_res.get('results'):
                movie_id = search_res['results'][0]['id']
                # 2. Get Details
                details_url = f"https://api.themoviedb.org/3/movie/{movie_id}?api_key={api_key}"
                with urllib.request.urlopen(details_url, timeout=5, context=_SSL_CTX) as det_response:
                    data = json.load(det_response)
                    return normalize_response('TMDB', data)
    except: pass
    return None

def fetch_yts(title, year):
    # Public API - No key needed!
    query = {'query_term': title} # YTS search is fuzzy
    url = f"https://yts.mx/api/v2/list_movies.json?{urllib.parse.urlencode(query)}"
    
    try:
        with urllib.request.urlopen(url, timeout=8, context=_SSL_CTX) as response:
            data = json.load(response)
            if data.get('data') and data['data'].get('movies'):
                # Filter by year if possible (YTS search is broad)
                movies = data['data']['movies']
                best_match = movies[0]
                
                if year:
                    for m in movies:
                        if str(m.get('year')) == str(year):
                            best_match = m
                            break
                            
                return normalize_response('YTS', best_match)
    except: pass
    return None

def fetch_google_metadata(title, year):
    """Scrape Google Search results for IMDB snippet"""
    query = f"{title} {year or ''} imdb"
    url = f"https://www.google.com/search?q={urllib.parse.quote(query)}"
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    }
    
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=5, context=_SSL_CTX) as response:
            html_content = response.read().decode('utf-8', errors='ignore')
            
            res = {
                'Year': year or '', 'Runtime': '', 'Genre': '', 'imdbRating': '', 
                'Plot': '', 'Response': 'True', 'Source': 'Google-Scrape'
            }
            
            # Robust Rating Regex
            # Matches: 8.7/10, 8.7 / 10, 8.7 out of 10
            rating_match = re.search(r'(\d+(?:\.\d+)?)\s*/\s*10', html_content)
            if rating_match:
                res['imdbRating'] = f"{rating_match.group(1)}/10"
                
            # Runtime Regex
            # Matches: 2h 16m, 2h 16min, 136 min
            runtime_match = re.search(r'(\d+h\s*\d+m)|(\d+\s*min)', html_content)
            if runtime_match:
                res['Runtime'] = runtime_match.group(0)
            
            # Genre
            common_genres = ['Action', 'Adventure', 'Sci-Fi', 'Drama', 'Comedy', 'Thriller', 'Horror', 'Romance', 'Fantasy', 'Animation', 'Crime', 'Mystery', 'Biography', 'History']
            found_genres = []
            for g in common_genres:
                if re.search(rf'\b{g}\b', html_content):
                    found_genres.append(g)
            if found_genres:
                # Deduplicate and limit
                seen = set()
                deduped = [x for x in found_genres if not (x in seen or seen.add(x))]
                res['Genre'] = ", ".join(deduped[:3])
                
            # Plot? (Hard to robustly scrape without clear markers)
            
            if res['imdbRating'] or res['Runtime']:
                return res
            
    except Exception as e:
        # Fail silently but could log if needed
        pass
    return None

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"Error": "No title provided"}))
        sys.exit(1)
        
    full_input = sys.argv[1]
    title, year = clean_title_and_year(full_input)
    
    # Prioritized Fallback Chain
    # 1. OMDB
    res = fetch_omdb(title, year)
    if res:
        print(json.dumps(res))
        return
        
    # 2. TMDB
    res = fetch_tmdb(title, year)
    if res:
        print(json.dumps(res))
        return
        
    # 3. YTS (Public)
    res = fetch_yts(title, year)
    if res:
        print(json.dumps(res))
        return

    # 4. Google Scrape (IMDB Snippet)
    res = fetch_google_metadata(title, year)
    if res:
        print(json.dumps(res))
        return
        
    # Failed
    print(json.dumps({"Error": "Not found"}))

if __name__ == "__main__":
    try:
        main()
    except Exception:
        print(json.dumps({"Error": "Script Exception"}))
