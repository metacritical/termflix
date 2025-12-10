#!/usr/bin/env python3
"""
TPB Catalog Fetcher - Fetches top movies and enriches with all torrents
"""
import json
import sys
import urllib.request
import urllib.parse
import re
import os

TPB_TOP100_URL = "https://apibay.org/precompiled/data_top100_207.json"
TPB_SEARCH_URL = "https://apibay.org/q.php"
OMDB_API_KEY = os.environ.get("OMDB_API_KEY", "")
TMDB_API_KEY = os.environ.get("TMDB_API_KEY", "")

def fetch_json(url, timeout=10):
    """Fetch JSON from URL"""
    try:
        req = urllib.request.Request(url, headers={
            'User-Agent': 'Mozilla/5.0'
        })
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception as e:
        return None

def extract_movie_info(name):
    """Extract movie title and year from torrent name"""
    # Replace separators with spaces
    name = re.sub(r'[._\-\+]', ' ', name)
    
    # Remove quality tags and other common suffixes
    quality_tags = ['1080p', '720p', '480p', '2160p', '4k', 'hdr', 'bluray', 'web dl', 'webrip', 
                    'hdrip', 'x264', 'x265', 'hevc', 'aac', 'cam', 'ts', 'tc', 'yts', 'yify', 'rarbg']
    for tag in quality_tags:
        name = re.sub(r'\b' + tag + r'\b', '', name, flags=re.IGNORECASE)
    
    # Match year pattern
    match = re.search(r'^(.+?)\s*(19\d{2}|20\d{2})\b', name)
    if match:
        title = match.group(1).strip()
        year = match.group(2)
        # Further normalize title: lowercase, collapse spaces
        title = re.sub(r'\s+', ' ', title).strip()
        return title, year
    
    return None, None

def get_omdb_info(imdb_id):
    """Fetch movie info from OMDB using IMDB ID"""
    if not OMDB_API_KEY or not imdb_id:
        return None
    
    url = f"http://www.omdbapi.com/?apikey={OMDB_API_KEY}&i={imdb_id}"
    data = fetch_json(url, timeout=5)
    
    if data and data.get('Response') == 'True':
        return {
            'title': data.get('Title', ''),
            'year': data.get('Year', ''),
            'plot': data.get('Plot', ''),
            'poster': data.get('Poster', ''),
            'imdb_rating': data.get('imdbRating', 'N/A'),
            'genre': data.get('Genre', ''),
            'runtime': data.get('Runtime', '')
        }
    return None

def get_tmdb_info(imdb_id):
    """Fetch movie info from TMDB using IMDB ID"""
    if not TMDB_API_KEY or not imdb_id:
        return None
    
    url = f"https://api.themoviedb.org/3/find/{imdb_id}?api_key={TMDB_API_KEY}&external_source=imdb_id"
    data = fetch_json(url, timeout=5)
    
    if data and data.get('movie_results'):
        movie = data['movie_results'][0]
        poster_path = movie.get('poster_path', '')
        return {
            'title': movie.get('title', ''),
            'year': movie.get('release_date', '')[:4] if movie.get('release_date') else '',
            'plot': movie.get('overview', ''),
            'poster': f"https://image.tmdb.org/t/p/w500{poster_path}" if poster_path else '',
            'vote_average': movie.get('vote_average', 0),
            'tmdb_id': movie.get('id', '')
        }
    return None

def search_tpb(query):
    """Search TPB for all torrents matching query"""
    encoded_query = urllib.parse.quote(query.replace(' ', '.'))
    url = f"{TPB_SEARCH_URL}?q={encoded_query}&cat=207"
    
    data = fetch_json(url, timeout=10)
    
    if data and isinstance(data, list):
        # Filter out "No results" placeholder
        return [t for t in data if t.get('id') != '0']
    
    return []

def format_size(size_bytes):
    """Format size in bytes to human readable"""
    try:
        size = int(size_bytes)
        if size >= 1024 * 1024 * 1024:
            return f"{size / (1024*1024*1024):.1f}GB"
        else:
            return f"{size // (1024*1024)}MB"
    except:
        return "N/A"

def main():
    """Main function - fetch TPB top 100 and enrich each movie"""
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 50
    fast_mode = '--fast' in sys.argv  # Fast mode skips slow API calls
    
    # Fetch TPB top 100
    top100 = fetch_json(TPB_TOP100_URL)
    
    if not top100:
        print("Error: Failed to fetch TPB data", file=sys.stderr)
        sys.exit(1)
    
    # Group by movie (title+year)
    movies = {}
    
    for torrent in top100[:limit]:
        name = torrent.get('name', '')
        title, year = extract_movie_info(name)
        
        if not title:
            continue
        
        key = f"{title.lower()}_{year}"
        
        if key not in movies:
            imdb_id = torrent.get('imdb', '')
            
            if fast_mode:
                # Fast mode: skip OMDB and extra search, use original torrent only
                omdb = None
                all_torrents = [torrent]
            else:
                # Full mode: Fetch metadata from OMDB (has IMDB rating)
                omdb = get_omdb_info(imdb_id) if imdb_id else None
                
                # Search TPB for all torrents of this movie
                search_query = f"{title} {year}"
                all_torrents = search_tpb(search_query)
                
                if not all_torrents:
                    all_torrents = [torrent]  # Use at least the original
            
            movies[key] = {
                'title': omdb['title'] if omdb else title,
                'year': omdb['year'] if omdb else year,
                'imdb_id': imdb_id,
                'imdb_rating': omdb['imdb_rating'] if omdb else 'N/A',
                'plot': omdb['plot'] if omdb else '',
                'poster': omdb['poster'] if omdb else '',
                'torrents': []
            }
            
            # Add all torrents
            seen_hashes = set()
            for t in all_torrents:
                info_hash = t.get('info_hash', '')
                if info_hash and info_hash not in seen_hashes:
                    seen_hashes.add(info_hash)
                    movies[key]['torrents'].append({
                        'name': t.get('name', ''),
                        'hash': info_hash,
                        'seeders': int(t.get('seeders', 0)),
                        'leechers': int(t.get('leechers', 0)),
                        'size': format_size(t.get('size', 0)),
                        'size_bytes': int(t.get('size', 0))
                    })
            
            # Sort torrents by seeders (highest first)
            movies[key]['torrents'].sort(key=lambda x: x['seeders'], reverse=True)
    
    # Output as JSON
    output = list(movies.values())
    print(json.dumps(output, indent=2))

if __name__ == "__main__":
    main()
