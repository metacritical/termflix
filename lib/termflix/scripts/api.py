#!/usr/bin/env python3
"""
Termflix API Module
Unified movie metadata API with OMDB, TMDB, YTS support.
Replaces: omdb.sh, tmdb.sh, and parts of posters.sh

Usage:
    # As module
    from api import TermflixAPI
    api = TermflixAPI()
    info = api.get_movie_info("The Matrix", 1999)
    
    # As CLI
    python3 api.py search "The Matrix" 1999
    python3 api.py poster "The Matrix"
    python3 api.py description "The Matrix"
"""
import sys
import os
import json
import hashlib
import urllib.request
import urllib.parse
import re
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Optional, Dict, Any
from dataclasses import dataclass
import time

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

CACHE_DIR = Path.home() / ".cache" / "termflix"
CONFIG_FILE = Path.home() / ".config" / "termflix" / "config"
CACHE_TTL = 7 * 24 * 60 * 60  # 7 days in seconds

# API endpoints
OMDB_BASE_URL = "http://www.omdbapi.com"
TMDB_BASE_URL = "https://api.themoviedb.org/3"
YTS_API_URL = "https://yts.mx/api/v2"


@dataclass
class MovieInfo:
    """Movie information container"""
    title: str = ""
    year: str = ""
    plot: str = ""
    poster: str = ""
    rating: str = "N/A"
    genre: str = ""
    runtime: str = ""
    imdb_id: str = ""
    source: str = ""
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'title': self.title,
            'year': self.year,
            'plot': self.plot,
            'poster': self.poster,
            'rating': self.rating,
            'genre': self.genre,
            'runtime': self.runtime,
            'imdb_id': self.imdb_id,
            'source': self.source
        }
    
    def to_json(self) -> str:
        return json.dumps(self.to_dict())


class TermflixAPI:
    """Unified API for fetching movie metadata"""
    
    def __init__(self):
        self._config = self._load_config()
        self.omdb_key = self._get_key('OMDB_API_KEY')
        self.tmdb_key = self._get_key('TMDB_API_KEY')
        
        # Ensure cache directories exist
        (CACHE_DIR / "omdb").mkdir(parents=True, exist_ok=True)
        (CACHE_DIR / "tmdb").mkdir(parents=True, exist_ok=True)
        (CACHE_DIR / "posters").mkdir(parents=True, exist_ok=True)
        (CACHE_DIR / "descriptions").mkdir(parents=True, exist_ok=True)
    
    def _load_config(self) -> Dict[str, str]:
        """Load config from file"""
        config = {}
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE) as f:
                    for line in f:
                        line = line.strip()
                        if '=' in line and not line.startswith('#'):
                            key, value = line.split('=', 1)
                            config[key.strip()] = value.strip().strip('"\'')
            except Exception:
                pass
        return config
    
    def _get_key(self, name: str) -> str:
        """Get API key from config or environment"""
        return self._config.get(name) or os.environ.get(name, '')
    
    @staticmethod
    def _cache_key(text: str) -> str:
        """Generate MD5 cache key from text"""
        normalized = re.sub(r'[^a-z0-9]', '', text.lower())
        return hashlib.md5(normalized.encode()).hexdigest()
    
    @staticmethod
    def _cache_valid(cache_file: Path) -> bool:
        """Check if cache file exists and is not expired"""
        if not cache_file.exists():
            return False
        file_age = time.time() - cache_file.stat().st_mtime
        return file_age < CACHE_TTL
    
    @staticmethod
    def _fetch_json(url: str, timeout: int = 5) -> Optional[Dict]:
        """Fetch JSON from URL"""
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=timeout) as response:
                return json.loads(response.read().decode('utf-8'))
        except Exception:
            return None
    
    # ═══════════════════════════════════════════════════════════════
    # OMDB API
    # ═══════════════════════════════════════════════════════════════
    
    def search_omdb(self, title: str, year: str = "") -> Optional[MovieInfo]:
        """Search OMDB for movie by title and optional year"""
        if not self.omdb_key:
            return None
        
        # Check cache
        cache_key = self._cache_key(f"{title}{year}")
        cache_file = CACHE_DIR / "omdb" / f"{cache_key}.json"
        
        if self._cache_valid(cache_file):
            try:
                data = json.loads(cache_file.read_text())
                if data.get('Response') == 'True':
                    return self._parse_omdb_response(data)
            except Exception:
                pass
        
        # Build URL
        encoded_title = urllib.parse.quote(title)
        url = f"{OMDB_BASE_URL}/?apikey={self.omdb_key}&t={encoded_title}&type=movie&plot=short"
        if year:
            url += f"&y={year}"
        
        # Fetch
        data = self._fetch_json(url)
        
        if data and data.get('Response') == 'True':
            cache_file.write_text(json.dumps(data))
            return self._parse_omdb_response(data)
        
        # Try search fallback
        search_url = f"{OMDB_BASE_URL}/?apikey={self.omdb_key}&s={encoded_title}&type=movie"
        if year:
            search_url += f"&y={year}"
        
        search_data = self._fetch_json(search_url)
        if search_data and search_data.get('Search'):
            imdb_id = search_data['Search'][0].get('imdbID', '')
            if imdb_id:
                detail_url = f"{OMDB_BASE_URL}/?apikey={self.omdb_key}&i={imdb_id}&plot=short"
                data = self._fetch_json(detail_url)
                if data and data.get('Response') == 'True':
                    cache_file.write_text(json.dumps(data))
                    return self._parse_omdb_response(data)
        
        return None
    
    def _parse_omdb_response(self, data: Dict) -> MovieInfo:
        """Parse OMDB API response into MovieInfo"""
        rating = data.get('imdbRating', 'N/A')
        if rating != 'N/A':
            rating = f"{rating}/10"
        
        poster = data.get('Poster', '')
        if poster == 'N/A':
            poster = ''
        
        return MovieInfo(
            title=data.get('Title', ''),
            year=data.get('Year', ''),
            plot=data.get('Plot', ''),
            poster=poster,
            rating=rating,
            genre=data.get('Genre', ''),
            runtime=data.get('Runtime', ''),
            imdb_id=data.get('imdbID', ''),
            source='omdb'
        )
    
    # ═══════════════════════════════════════════════════════════════
    # TMDB API
    # ═══════════════════════════════════════════════════════════════
    
    def search_tmdb(self, title: str, year: str = "") -> Optional[MovieInfo]:
        """Search TMDB for movie by title and optional year"""
        if not self.tmdb_key:
            return None
        
        # Check cache
        cache_key = self._cache_key(f"{title}{year}")
        cache_file = CACHE_DIR / "tmdb" / f"{cache_key}.json"
        
        if self._cache_valid(cache_file):
            try:
                data = json.loads(cache_file.read_text())
                return self._parse_tmdb_response(data)
            except Exception:
                pass
        
        # Build URL
        encoded_title = urllib.parse.quote(title)
        url = f"{TMDB_BASE_URL}/search/movie?api_key={self.tmdb_key}&query={encoded_title}"
        if year:
            url += f"&year={year}"
        
        # Fetch
        data = self._fetch_json(url)
        
        if data and data.get('results'):
            result = data['results'][0]
            cache_file.write_text(json.dumps(result))
            return self._parse_tmdb_response(result)
        
        return None
    
    def _parse_tmdb_response(self, data: Dict) -> MovieInfo:
        """Parse TMDB API response into MovieInfo"""
        poster_path = data.get('poster_path', '')
        poster = f"https://image.tmdb.org/t/p/w500{poster_path}" if poster_path else ''
        
        rating = data.get('vote_average', 0)
        rating_str = f"{rating:.1f}/10" if rating > 0 else 'N/A'
        
        release_date = data.get('release_date', '')
        year = release_date[:4] if release_date else ''
        
        return MovieInfo(
            title=data.get('title', ''),
            year=year,
            plot=data.get('overview', ''),
            poster=poster,
            rating=rating_str,
            source='tmdb'
        )
    
    # ═══════════════════════════════════════════════════════════════
    # YTS API
    # ═══════════════════════════════════════════════════════════════
    
    def search_yts(self, title: str) -> Optional[MovieInfo]:
        """Search YTS for movie poster (public API, no key needed)"""
        clean_title = title.split('(')[0].strip()
        encoded_title = urllib.parse.quote(clean_title)
        url = f"{YTS_API_URL}/list_movies.json?query_term={encoded_title}&limit=1"
        
        data = self._fetch_json(url)
        
        if data and data.get('status') == 'ok':
            movies = data.get('data', {}).get('movies', [])
            if movies:
                movie = movies[0]
                return MovieInfo(
                    title=movie.get('title', ''),
                    year=str(movie.get('year', '')),
                    plot=movie.get('summary', '')[:200] if movie.get('summary') else '',
                    poster=movie.get('medium_cover_image', '') or movie.get('large_cover_image', ''),
                    rating=f"{movie.get('rating', 0)}/10" if movie.get('rating') else 'N/A',
                    genre='/'.join(movie.get('genres', [])[:3]),
                    runtime=f"{movie.get('runtime', 0)} min",
                    imdb_id=movie.get('imdb_code', ''),
                    source='yts'
                )
        
        return None
    
    # ═══════════════════════════════════════════════════════════════
    # UNIFIED API
    # ═══════════════════════════════════════════════════════════════
    
    def get_movie_info(self, title: str, year: str = "") -> Optional[MovieInfo]:
        """
        Get movie info with fallback chain: OMDB → TMDB → YTS
        Uses parallel fetching for speed.
        """
        # Try all sources in parallel
        with ThreadPoolExecutor(max_workers=3) as executor:
            futures = {}
            
            if self.omdb_key:
                futures[executor.submit(self.search_omdb, title, year)] = 'omdb'
            if self.tmdb_key:
                futures[executor.submit(self.search_tmdb, title, year)] = 'tmdb'
            futures[executor.submit(self.search_yts, title)] = 'yts'
            
            # Return first successful result
            for future in as_completed(futures):
                try:
                    result = future.result()
                    if result and (result.plot or result.poster):
                        return result
                except Exception:
                    continue
        
        return None
    
    def get_poster_url(self, title: str, year: str = "") -> str:
        """Get poster URL with fallback chain"""
        info = self.get_movie_info(title, year)
        if info and info.poster:
            return info.poster
        return ""
    
    def get_description(self, title: str, year: str = "") -> str:
        """Get movie description with fallback chain"""
        info = self.get_movie_info(title, year)
        if info and info.plot:
            return info.plot
        return ""
    
    def get_rating(self, title: str, year: str = "") -> str:
        """Get movie rating with fallback chain"""
        info = self.get_movie_info(title, year)
        if info and info.rating:
            return info.rating
        return "N/A"
    
    def get_rating_by_imdb_id(self, imdb_id: str) -> str:
        """Get IMDB rating using IMDB ID (e.g., tt31227572)"""
        if not imdb_id or not self.omdb_key:
            return "N/A"
        
        # Normalize IMDB ID
        if not imdb_id.startswith('tt'):
            imdb_id = f"tt{imdb_id}"
        
        # Check cache
        cache_file = CACHE_DIR / "omdb" / f"{imdb_id}.json"
        
        if self._cache_valid(cache_file):
            try:
                data = json.loads(cache_file.read_text())
                rating = data.get('imdbRating', 'N/A')
                return f"⭐ {rating}" if rating != 'N/A' else 'N/A'
            except:
                pass
        
        # Fetch from OMDB
        url = f"{OMDB_BASE_URL}/?apikey={self.omdb_key}&i={imdb_id}"
        data = self._fetch_json(url)
        
        if data and data.get('Response') == 'True':
            cache_file.write_text(json.dumps(data))
            rating = data.get('imdbRating', 'N/A')
            return f"⭐ {rating}" if rating != 'N/A' else 'N/A'
        
        return "N/A"
    
    def get_ratings_batch(self, imdb_ids: list) -> Dict[str, str]:
        """Fetch ratings for multiple IMDB IDs in parallel"""
        results = {}
        
        with ThreadPoolExecutor(max_workers=10) as executor:
            future_to_id = {
                executor.submit(self.get_rating_by_imdb_id, imdb_id): imdb_id 
                for imdb_id in imdb_ids if imdb_id
            }
            
            for future in as_completed(future_to_id):
                imdb_id = future_to_id[future]
                try:
                    results[imdb_id] = future.result()
                except:
                    results[imdb_id] = "N/A"
        
        return results


# ═══════════════════════════════════════════════════════════════
# CLI INTERFACE
# ═══════════════════════════════════════════════════════════════

def main():
    """CLI interface for bash scripts to call"""
    if len(sys.argv) < 2:
        print("Usage: api.py <command> <title> [year]", file=sys.stderr)
        print("Commands: search, poster, description, rating, info", file=sys.stderr)
        sys.exit(1)
    
    command = sys.argv[1]
    title = sys.argv[2] if len(sys.argv) > 2 else ""
    year = sys.argv[3] if len(sys.argv) > 3 else ""
    
    if not title:
        print("Error: title required", file=sys.stderr)
        sys.exit(1)
    
    api = TermflixAPI()
    
    if command == 'search' or command == 'info':
        info = api.get_movie_info(title, year)
        if info:
            print(info.to_json())
        else:
            print('{"error": "Not found"}')
    
    elif command == 'poster':
        poster = api.get_poster_url(title, year)
        print(poster if poster else "null")
    
    elif command == 'description' or command == 'plot':
        desc = api.get_description(title, year)
        print(desc if desc else "")
    
    elif command == 'rating':
        rating = api.get_rating(title, year)
        print(rating)
    
    elif command == 'omdb':
        info = api.search_omdb(title, year)
        if info:
            print(info.to_json())
        else:
            print('{"error": "Not found"}')
    
    elif command == 'tmdb':
        info = api.search_tmdb(title, year)
        if info:
            print(info.to_json())
        else:
            print('{"error": "Not found"}')
    
    elif command == 'yts':
        info = api.search_yts(title)
        if info:
            print(info.to_json())
        else:
            print('{"error": "Not found"}')
    
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
