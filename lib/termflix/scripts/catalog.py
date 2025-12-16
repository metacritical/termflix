#!/usr/bin/env python3
"""
Termflix Catalog Fetcher Module
Fetches movie/show catalogs from YTS, TPB, and EZTV APIs.
Replaces: catalog.sh fetching functions

Usage:
    # As module
    from catalog import CatalogFetcher
    fetcher = CatalogFetcher()
    movies = fetcher.get_trending(limit=20)
    
    # As CLI
    python3 catalog.py latest [limit] [page]
    python3 catalog.py trending [limit] [page]
    python3 catalog.py popular [limit] [page]
    python3 catalog.py shows [limit] [page]
    python3 catalog.py genre <genre> [limit]
"""
import sys
import json
import urllib.request
import urllib.parse
from typing import Optional, List, Dict, Any
from dataclasses import dataclass, field
from concurrent.futures import ThreadPoolExecutor, as_completed
import re

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

YTS_API = "https://yts.mx/api/v2/list_movies.json"
TPB_TOP100_MOVIES = "https://apibay.org/precompiled/data_top100_207.json"
TPB_TOP100_VIDEO = "https://apibay.org/precompiled/data_top100_201.json"
TPB_TOP100_TV = "https://apibay.org/precompiled/data_top100_205.json"
TPB_SEARCH_URL = "https://apibay.org/q.php"
EZTV_API = "https://eztv.re/api/get-torrents"

# Caching Configuration
from pathlib import Path
import time
import hashlib

CACHE_BASE = Path.home() / ".cache" / "termflix"
CATALOG_CACHE_DIR = CACHE_BASE / "catalog"
CATALOG_CACHE_TTL = 3600  # 1 hour for catalog results
SEARCH_CACHE_TTL = 1800   # 30 min for search results

# Ensure cache directories exist
CATALOG_CACHE_DIR.mkdir(parents=True, exist_ok=True)

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    'Accept': 'application/json'
}

# Genre mapping (same as YTS-Streaming app)
GENRE_MAP = {
    'action': 'Action',
    'adventure': 'Adventure',
    'animation': 'Animation',
    'comedy': 'Comedy',
    'crime': 'Crime',
    'documentary': 'Documentary',
    'drama': 'Drama',
    'family': 'Family',
    'fantasy': 'Fantasy',
    'horror': 'Horror',
    'mystery': 'Mystery',
    'romance': 'Romance',
    'sci-fi': 'Sci-Fi',
    'scifi': 'Sci-Fi',
    'science-fiction': 'Sci-Fi',
    'thriller': 'Thriller',
    'war': 'War',
    'western': 'Western'
}


@dataclass
class CatalogItem:
    """A single catalog entry"""
    source: str = ""
    name: str = ""
    magnet: str = ""
    quality: str = ""
    size: str = ""
    extra: str = ""  # IMDB ID like tt31227572
    poster: str = ""
    rating: str = ""  # IMDB rating like ⭐ 7.5
    
    def to_pipe_format(self) -> str:
        """Convert to pipe-delimited format for bash consumption
        Format: source|name|magnet|quality|size|imdb_id|poster|rating
        """
        return f"{self.source}|{self.name}|{self.magnet}|{self.quality}|{self.size}|{self.extra}|{self.poster}|{self.rating}"
    
    def to_dict(self) -> Dict[str, str]:
        return {
            'source': self.source,
            'name': self.name,
            'magnet': self.magnet,
            'quality': self.quality,
            'size': self.size,
            'extra': self.extra,
            'poster': self.poster,
            'rating': self.rating
        }

class CatalogFetcher:
    """Fetches movie/show catalogs from various sources with caching"""
    
    @staticmethod
    def _fetch_json(url: str, timeout: int = 10) -> Optional[Dict]:
        """Fetch JSON from URL"""
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=timeout) as response:
                return json.loads(response.read().decode('utf-8'))
        except Exception:
            return None
    
    @staticmethod
    def _format_size(size_bytes: int) -> str:
        """Format bytes as human-readable size"""
        try:
            size = int(size_bytes)
            if size >= 1024 * 1024 * 1024:
                return f"{size / (1024*1024*1024):.1f}GB"
            return f"{size // (1024*1024)}MB"
        except:
            return "N/A"
    
    # ═══════════════════════════════════════════════════════════════
    # CACHING METHODS
    # ═══════════════════════════════════════════════════════════════
    
    @staticmethod
    def _cache_key(category: str, *args) -> str:
        """Generate cache key from category and arguments"""
        key_str = f"{category}_" + "_".join(str(a) for a in args)
        return hashlib.md5(key_str.encode()).hexdigest()
    
    @staticmethod
    def _cache_valid(cache_file: Path, ttl: int = CATALOG_CACHE_TTL) -> bool:
        """Check if cache file is valid (exists and not expired)"""
        if not cache_file.exists():
            return False
        file_age = time.time() - cache_file.stat().st_mtime
        return file_age < ttl
    
    @staticmethod
    def _load_cache(cache_file: Path) -> Optional[List[Dict]]:
        """Load cached items from file"""
        try:
            if cache_file.exists():
                return json.loads(cache_file.read_text())
        except:
            pass
        return None
    
    @staticmethod
    def _save_cache(cache_file: Path, items: List['CatalogItem']):
        """Save items to cache file"""
        try:
            data = [item.to_dict() for item in items]
            cache_file.write_text(json.dumps(data))
        except:
            pass
    
    # YTS API
    # ═══════════════════════════════════════════════════════════════
    
    def get_yts_movies(self, sort_by: str = "date_added", limit: int = 20, 
                       page: int = 1, genre: str = "", 
                       min_rating: int = 0) -> List[CatalogItem]:
        """Fetch movies from YTS API - returns ALL torrents per movie"""
        params = {
            'limit': limit,
            'page': page,
            'sort_by': sort_by,
            'order_by': 'desc'
        }
        
        if genre:
            params['genre'] = GENRE_MAP.get(genre.lower(), genre)
        if min_rating > 0:
            params['minimum_rating'] = min_rating
        
        url = f"{YTS_API}?{urllib.parse.urlencode(params)}"
        data = self._fetch_json(url, timeout=5)
        
        if not data or data.get('status') != 'ok':
            return []
        
        items = []
        movies = data.get('data', {}).get('movies', [])
        
        for movie in movies:
            torrents = movie.get('torrents', [])
            if not torrents:
                continue
            
            title = movie.get('title', '')
            year = movie.get('year', '')
            rating = movie.get('rating', 0)
            poster = movie.get('medium_cover_image', 'N/A')
            
            # Return ALL torrents for this movie
            for torrent in torrents:
                if not torrent.get('hash'):
                    continue
                
                quality = torrent.get('quality', 'N/A')
                name = f"{title} ({year}) [{quality}]"
                if sort_by == 'rating' and rating:
                    name = f"{title} ({year}) [{quality}] ⭐{rating}"
                
                items.append(CatalogItem(
                    source='YTS',
                    name=name,
                    magnet=f"magnet:?xt=urn:btih:{torrent['hash']}",
                    quality=quality,
                    size=torrent.get('size', 'N/A'),
                    extra=str(movie.get('download_count', 0)) if sort_by == 'download_count' 
                          else str(rating) if sort_by == 'rating'
                          else ', '.join(movie.get('genres', [])[:2]),
                    poster=poster
                ))
        
        return items
    
    def search_yts(self, query: str, limit: int = 10) -> List[CatalogItem]:
        """Search YTS for a movie by title - returns ALL quality options"""
        encoded = urllib.parse.quote(query)
        url = f"{YTS_API}?query_term={encoded}&limit={limit}"
        
        data = self._fetch_json(url, timeout=5)
        
        if not data or data.get('status') != 'ok':
            return []
        
        items = []
        movies = data.get('data', {}).get('movies', [])
        
        for movie in movies:
            torrents = movie.get('torrents', [])
            if not torrents:
                continue
            
            title = movie.get('title', '')
            year = movie.get('year', '')
            poster = movie.get('medium_cover_image', 'N/A')
            
            # Return ALL torrents for this movie
            for torrent in torrents:
                if not torrent.get('hash'):
                    continue
                
                quality = torrent.get('quality', 'N/A')
                items.append(CatalogItem(
                    source='YTS',
                    name=f"{title} ({year}) [{quality}]",
                    magnet=f"magnet:?xt=urn:btih:{torrent['hash']}",
                    quality=quality,
                    size=torrent.get('size', 'N/A'),
                    extra=str(torrent.get('seeds', 0)),
                    poster=poster
                ))
        
        return items
    
    def get_trending(self, limit: int = 20, page: int = 1) -> List[CatalogItem]:
        """Get trending movies (sorted by download count)"""
        items = self.get_yts_movies(
            sort_by='download_count',
            limit=limit,
            page=page
        )
        
        if not items:
            # Fallback to TPB
            items = self.get_tpb_catalog(TPB_TOP100_VIDEO, limit)
        
        return items
    
    def get_popular(self, limit: int = 20, page: int = 1) -> List[CatalogItem]:
        """Get popular movies (sorted by rating, min 7.0)"""
        items = self.get_yts_movies(
            sort_by='rating',
            limit=limit,
            page=page,
            min_rating=7
        )
        
        if not items:
            # Fallback to TPB
            items = self.get_tpb_catalog(TPB_TOP100_TV, limit)
        
        return items
    
    def get_by_genre(self, genre: str, limit: int = 20) -> List[CatalogItem]:
        """Get movies by genre"""
        return self.get_yts_movies(
            sort_by='date_added',
            limit=limit,
            genre=genre
        )
    
    # ═══════════════════════════════════════════════════════════════
    # TPB API
    # ═══════════════════════════════════════════════════════════════
    
    def get_tpb_catalog(self, url: str = TPB_TOP100_MOVIES, 
                        limit: int = 50) -> List[CatalogItem]:
        """Fetch catalog from TPB precompiled data"""
        data = self._fetch_json(url, timeout=10)
        
        if not data or not isinstance(data, list):
            return []
        
        items = []
        for torrent in data[:limit]:
            info_hash = torrent.get('info_hash', '')
            if not info_hash or info_hash == '0' * 40:
                continue
            
            items.append(CatalogItem(
                source='TPB',
                name=torrent.get('name', 'Unknown'),
                magnet=f"magnet:?xt=urn:btih:{info_hash}",
                quality=f"{torrent.get('seeders', 0)} seeds",
                size=self._format_size(torrent.get('size', 0)),
                extra=torrent.get('imdb', 'N/A'),
                poster='N/A'
            ))
        
        return items
    
    def search_tpb(self, query: str, limit: int = 10) -> List[CatalogItem]:
        """Search TPB for torrents matching query"""
        encoded = urllib.parse.quote(query.replace(' ', '.'))
        url = f"{TPB_SEARCH_URL}?q={encoded}&cat=207"  # 207 = HD Movies
        
        data = self._fetch_json(url, timeout=8)
        if not data or not isinstance(data, list):
            return []
        
        items = []
        for torrent in data[:limit]:
            if torrent.get('id') == '0':  # "No results" placeholder
                continue
            
            info_hash = torrent.get('info_hash', '')
            if not info_hash:
                continue
            
            items.append(CatalogItem(
                source='TPB',
                name=torrent.get('name', 'Unknown'),
                magnet=f"magnet:?xt=urn:btih:{info_hash}",
                quality=f"{torrent.get('seeders', 0)} seeds",
                size=self._format_size(torrent.get('size', 0)),
                extra=torrent.get('imdb', 'N/A'),
                poster='N/A'
            ))
        
        return items
    
    def search_1337x(self, query: str, limit: int = 5) -> List[CatalogItem]:
        """Search 1337x for torrents (scrapes HTML)"""
        import re
        encoded = urllib.parse.quote(query)
        search_url = f"https://1337x.to/search/{encoded}/1/"
        
        try:
            req = urllib.request.Request(search_url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=8) as response:
                html = response.read().decode('utf-8', errors='ignore')
            
            # Extract torrent links
            pattern = r'/torrent/(\d+)/([^/]+)/'
            matches = re.findall(pattern, html)[:limit]
            
            items = []
            for torrent_id, name in matches:
                # Get magnet from torrent page
                torrent_url = f"https://1337x.to/torrent/{torrent_id}/{name}/"
                try:
                    req2 = urllib.request.Request(torrent_url, headers=HEADERS)
                    with urllib.request.urlopen(req2, timeout=5) as resp2:
                        page = resp2.read().decode('utf-8', errors='ignore')
                    
                    magnet_match = re.search(r'magnet:\?xt=urn:btih:[a-fA-F0-9]+', page)
                    if magnet_match:
                        items.append(CatalogItem(
                            source='1337x',
                            name=name.replace('-', ' '),
                            magnet=magnet_match.group(0),
                            quality='N/A',
                            size='N/A',
                            extra='N/A',
                            poster='N/A'
                        ))
                except:
                    continue
            
            return items
        except:
            return []
    
    def get_latest(self, limit: int = 20, page: int = 1) -> List[CatalogItem]:
        """Get latest movies from TPB top 100"""
        return self.get_tpb_catalog(TPB_TOP100_MOVIES, limit)
    
    # ═══════════════════════════════════════════════════════════════
    # MULTI-SOURCE ENRICHMENT
    # ═══════════════════════════════════════════════════════════════
    
    def _extract_movie_title(self, name: str) -> tuple:
        """Extract clean movie title and year from torrent name"""
        import re
        
        # Replace separators
        name = re.sub(r'[._\-\+]', ' ', name)
        
        # Remove quality tags
        quality_tags = ['1080p', '720p', '480p', '2160p', '4k', 'hdr', 'bluray', 
                       'webrip', 'web dl', 'hdrip', 'x264', 'x265', 'hevc', 
                       'yts', 'yify', 'rarbg', 'extended', 'remastered']
        for tag in quality_tags:
            name = re.sub(rf'\b{tag}\b', '', name, flags=re.IGNORECASE)
        
        # Extract year
        match = re.search(r'^(.+?)\s*[\(\[]?\s*(19\d{2}|20\d{2})\s*[\)\]]?', name)
        if match:
            title = match.group(1).strip()
            year = match.group(2)
            # Clean title
            title = re.sub(r'\([^)]*\)', '', title)
            title = re.sub(r'\[[^\]]*\]', '', title)
            title = re.sub(r'[^a-zA-Z0-9 ]', '', title)
            title = re.sub(r'\s+', ' ', title).strip()
            return title, year
        
        return None, None
    
    def get_enriched_catalog(self, limit: int = 20, 
                             search_per_movie: int = 5) -> List[CatalogItem]:
        """
        Get enriched catalog with multi-source search (CACHED).
        
        1. Check cache first (TTL: 1 hour)
        2. Fetch TPB top 100 movies
        3. For each unique movie, search TPB and YTS for all torrents
        4. Combine, deduplicate, and cache results
        """
        # Check cache first
        cache_key = self._cache_key("enriched", limit, search_per_movie)
        cache_file = CATALOG_CACHE_DIR / f"{cache_key}.json"
        
        if self._cache_valid(cache_file, CATALOG_CACHE_TTL):
            cached_data = self._load_cache(cache_file)
            if cached_data:
                # Reconstruct CatalogItem objects from cached dicts
                items = []
                for d in cached_data:
                    items.append(CatalogItem(**d))
                return items
        
        # Step 1: Get TPB top 100
        tpb_items = self.get_tpb_catalog(TPB_TOP100_MOVIES, limit * 2)
        
        if not tpb_items:
            return []
        
        # Step 2: Group by movie title
        seen_titles = {}
        for item in tpb_items:
            title, year = self._extract_movie_title(item.name)
            if not title:
                continue
            
            key = f"{title.lower()}_{year}"
            if key not in seen_titles:
                seen_titles[key] = {
                    'title': title,
                    'year': year,
                    'items': [],
                    'seen_magnets': set()
                }
            
            # Add item if not duplicate
            magnet_hash = item.magnet.split(':')[-1][:40] if 'btih:' in item.magnet else item.magnet
            if magnet_hash not in seen_titles[key]['seen_magnets']:
                seen_titles[key]['seen_magnets'].add(magnet_hash)
                seen_titles[key]['items'].append(item)
        
        # Step 3: Search for each movie in parallel on TPB + YTS
        all_results = []
        
        with ThreadPoolExecutor(max_workers=8) as executor:
            futures = {}
            
            for key, movie_data in list(seen_titles.items())[:limit]:
                search_query = f"{movie_data['title']} {movie_data['year']}"
                
                # Search TPB for ALL available torrents
                futures[executor.submit(self.search_tpb, search_query, 20)] = (key, 'tpb')
                
                # Search YTS for ALL quality options
                futures[executor.submit(self.search_yts, search_query, 5)] = (key, 'yts')
            
            for future in as_completed(futures):
                key, source = futures[future]
                try:
                    results = future.result()
                    if results and key in seen_titles:
                        for item in results:
                            magnet_hash = item.magnet.split(':')[-1][:40] if 'btih:' in item.magnet else item.magnet
                            if magnet_hash not in seen_titles[key]['seen_magnets']:
                                seen_titles[key]['seen_magnets'].add(magnet_hash)
                                seen_titles[key]['items'].append(item)
                except:
                    pass
        
        # Step 4: Flatten and return ALL torrents (no per-movie limit)
        all_results = []
        for key, movie_data in seen_titles.items():
            # Sort by seeders (extract number from quality string)
            def get_seeds(item):
                import re
                match = re.search(r'(\d+)\s*seeds?', item.quality)
                return int(match.group(1)) if match else 0
            
            movie_data['items'].sort(key=get_seeds, reverse=True)
            # Return ALL torrents for this movie, not just a subset
            all_results.extend(movie_data['items'])
        
        # Step 5: Enrich with IMDB ratings
        try:
            from api import TermflixAPI
            api = TermflixAPI()
            
            # Collect unique IMDB IDs
            imdb_ids = set()
            for item in all_results:
                if item.extra and item.extra.startswith('tt'):
                    imdb_ids.add(item.extra)
            
            if imdb_ids:
                # Fetch ratings in parallel
                ratings = api.get_ratings_batch(list(imdb_ids))
                
                # Apply ratings to items
                for item in all_results:
                    if item.extra in ratings:
                        item.rating = ratings[item.extra]
        except Exception:
            pass  # Rating enrichment is optional
        
        # Save to cache before returning
        self._save_cache(cache_file, all_results)
        
        return all_results
    
    # ═══════════════════════════════════════════════════════════════
    # EZTV API
    # ═══════════════════════════════════════════════════════════════
    
    def get_shows(self, limit: int = 20, page: int = 1) -> List[CatalogItem]:
        """Get latest TV shows from TPB (EZTV API is blocked)"""
        # TPB TV Shows: category 205 (Video - TV Shows)
        url = TPB_TOP100_TV
        data = self._fetch_json(url, timeout=10)
        
        if not data or not isinstance(data, list):
            return []
        
        items = []
        for torrent in data[:limit]:
            info_hash = torrent.get('info_hash', '')
            if not info_hash:
                continue
            
            name = torrent.get('name', 'Unknown')
            magnet = f"magnet:?xt=urn:btih:{info_hash}"
            seeds = torrent.get('seeders', 0)
            size = self._format_size(torrent.get('size', 0))
            
            items.append(CatalogItem(
                source='TPB',
                name=name,
                magnet=magnet,
                quality=f"{seeds} seeds",
                size=size,
                extra=str(seeds),
                poster='N/A'
            ))
        
        return items
    
    # ═══════════════════════════════════════════════════════════════
    # COMBINED CATALOG
    # ═══════════════════════════════════════════════════════════════
    
    def get_all(self, catalog_type: str = "latest", limit: int = 20, 
                page: int = 1, genre: str = "") -> List[CatalogItem]:
        """
        Get catalog based on type.
        
        Args:
            catalog_type: 'latest', 'trending', 'popular', 'shows', 'genre'
            limit: Number of items per page
            page: Page number (1-indexed)
            genre: Genre for 'genre' type
        """
        if catalog_type == 'latest':
            return self.get_latest(limit, page)
        elif catalog_type == 'trending':
            return self.get_trending(limit, page)
        elif catalog_type == 'popular':
            return self.get_popular(limit, page)
        elif catalog_type == 'shows':
            return self.get_shows(limit, page)
        elif catalog_type == 'genre' and genre:
            return self.get_by_genre(genre, limit)
        else:
            return self.get_latest(limit, page)


# ═══════════════════════════════════════════════════════════════
# CLI INTERFACE
# ═══════════════════════════════════════════════════════════════

def main():
    """CLI interface for bash scripts"""
    if len(sys.argv) < 2:
        print("Usage: catalog.py <command> [args...]", file=sys.stderr)
        print("Commands: latest, trending, popular, shows, genre", file=sys.stderr)
        sys.exit(1)
    
    command = sys.argv[1]
    fetcher = CatalogFetcher()
    
    # Parse common args: limit and page
    limit = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 20
    page = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else 1
    
    items = []
    
    if command == 'latest':
        items = fetcher.get_latest(limit, page)
    
    elif command == 'trending':
        items = fetcher.get_trending(limit, page)
    
    elif command == 'popular':
        items = fetcher.get_popular(limit, page)
    
    elif command == 'shows':
        items = fetcher.get_shows(limit, page)
    
    elif command == 'genre':
        if len(sys.argv) < 3:
            print("Usage: catalog.py genre <genre_name> [limit]", file=sys.stderr)
            sys.exit(1)
        genre = sys.argv[2]
        limit = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else 20
        items = fetcher.get_by_genre(genre, limit)
    
    elif command == 'enriched':
        # Multi-source enriched catalog
        search_per = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else 5
        items = fetcher.get_enriched_catalog(limit, search_per)
    
    elif command == 'search':
        # Search TPB for a query
        if len(sys.argv) < 3:
            print("Usage: catalog.py search <query> [limit]", file=sys.stderr)
            sys.exit(1)
        query = sys.argv[2]
        limit = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else 10
        items = fetcher.search_tpb(query, limit)
    
    elif command == 'json':
        # Output as JSON for advanced usage
        catalog_type = sys.argv[2] if len(sys.argv) > 2 else 'latest'
        genre = sys.argv[3] if len(sys.argv) > 3 and catalog_type == 'genre' else ''
        items = fetcher.get_all(catalog_type, limit, page, genre)
        print(json.dumps([item.to_dict() for item in items], indent=2))
        return
    
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        print("Available: latest, trending, popular, shows, genre, json", file=sys.stderr)
        sys.exit(1)
    
    # Output as pipe-delimited format (for bash consumption)
    for item in items:
        print(item.to_pipe_format())


if __name__ == "__main__":
    main()
