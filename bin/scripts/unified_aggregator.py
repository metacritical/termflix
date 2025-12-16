#!/usr/bin/env python3
"""
Unified Torrent Aggregator
Merges torrents from TPB, YTS, 1337x into deduplicated movie collections
"""
import re
import json
import sys
import os
from typing import Dict, List, Set
from collections import defaultdict

# Add scripts dir for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def normalize_title(title: str) -> str:
    """
    Normalize movie title for matching across sources.
    "The Matrix" and "Matrix, The" should match.
    """
    if not title:
        return ""
    
    # Lowercase
    t = title.lower().strip()
    
    # Remove "the " prefix or ", the" suffix
    t = re.sub(r'^the\s+', '', t)
    t = re.sub(r',\s*the$', '', t)
    
    # Remove special characters except spaces
    t = re.sub(r'[^\w\s]', '', t)
    
    # Collapse multiple spaces
    t = re.sub(r'\s+', ' ', t).strip()
    
    return t


def extract_year(text: str) -> str:
    """Extract 4-digit year from text"""
    match = re.search(r'\b(19\d{2}|20\d{2})\b', text)
    return match.group(1) if match else ""


def extract_quality(name: str) -> str:
    """Extract quality from torrent name"""
    name_lower = name.lower()
    qualities = [
        ('2160p', '4K'), ('4k', '4K'), ('uhd', '4K'),
        ('1080p', '1080p'), ('1080i', '1080p'),
        ('720p', '720p'),
        ('480p', '480p'),
        ('cam', 'CAM'), ('ts', 'TS'), ('tc', 'TC'),
    ]
    for pattern, label in qualities:
        if pattern in name_lower:
            return label
    return 'Unknown'


def extract_source_type(name: str) -> str:
    """Extract source type (BluRay, WEB-DL, etc.)"""
    name_lower = name.lower()
    sources = [
        ('bluray', 'BluRay'), ('blu-ray', 'BluRay'), ('bdrip', 'BluRay'),
        ('web-dl', 'WEB-DL'), ('webdl', 'WEB-DL'), ('webrip', 'WEBRip'),
        ('hdrip', 'HDRip'), ('dvdrip', 'DVDRip'),
        ('hdtv', 'HDTV'),
    ]
    for pattern, label in sources:
        if pattern in name_lower:
            return label
    return ''


def format_size(size_bytes) -> str:
    """Format bytes to human readable"""
    try:
        size = int(size_bytes)
        if size >= 1024**3:
            return f"{size / 1024**3:.1f}GB"
        return f"{size // 1024**2}MB"
    except:
        return "N/A"


class UnifiedAggregator:
    """
    Aggregates torrents from multiple sources into unified movie collections.
    Deduplicates by info_hash to prevent duplicate torrents.
    """
    
    def __init__(self):
        # Key: normalized_title_year, Value: movie dict with torrents
        self.movies: Dict[str, Dict] = {}
        # Track seen hashes to prevent duplicates
        self.seen_hashes: Set[str] = set()
    
    def _get_movie_key(self, title: str, year: str) -> str:
        """Generate unique key for a movie"""
        norm_title = normalize_title(title)
        return f"{norm_title}_{year}" if year else norm_title
    
    def add_torrent(self, 
                    source: str,  # "TPB", "YTS", "1337x"
                    title: str,
                    year: str,
                    name: str,  # Full torrent name
                    info_hash: str,
                    seeders: int,
                    leechers: int = 0,
                    size_bytes: int = 0,
                    imdb_id: str = "",
                    poster: str = "",
                    rating: str = ""):
        """
        Add a torrent to the aggregator.
        Automatically groups by movie and deduplicates by hash.
        """
        # Skip invalid hashes
        if not info_hash or info_hash == '0' * 40:
            return
        
        # Skip duplicates
        if info_hash.lower() in self.seen_hashes:
            return
        
        self.seen_hashes.add(info_hash.lower())
        
        key = self._get_movie_key(title, year)
        
        # Create movie entry if needed
        if key not in self.movies:
            self.movies[key] = {
                'title': title,
                'year': year,
                'imdb_id': imdb_id,
                'poster': poster,
                'rating': rating,
                'sources': set(),  # Track which sources have torrents
                'torrents': []
            }
        
        movie = self.movies[key]
        
        # Update metadata if better version available
        if imdb_id and not movie['imdb_id']:
            movie['imdb_id'] = imdb_id
        if poster and not movie['poster']:
            movie['poster'] = poster
        if rating and movie['rating'] in ('', 'N/A'):
            movie['rating'] = rating
        
        # Add source to set
        movie['sources'].add(source)
        
        # Build torrent entry
        quality = extract_quality(name)
        source_type = extract_source_type(name)
        
        # Link type: always prefer magnets
        link_type = 'magnet'
        
        torrent = {
            'source': source,
            'name': name,
            'hash': info_hash,
            'link_type': link_type,
            'magnet': f"magnet:?xt=urn:btih:{info_hash}",
            'quality': quality,
            'source_type': source_type,
            'seeders': int(seeders),
            'leechers': int(leechers),
            'size': format_size(size_bytes),
            'size_bytes': int(size_bytes)
        }
        
        movie['torrents'].append(torrent)
    
    def add_tpb_results(self, results: List[Dict], title_override: str = None, year_override: str = None):
        """Add TPB search results to aggregator"""
        for item in results:
            name = item.get('name', '')
            info_hash = item.get('info_hash', '')
            
            # Extract title/year from torrent name if not provided
            if title_override and year_override:
                title, year = title_override, year_override
            else:
                from fetch_tpb_catalog import extract_movie_info
                title, year = extract_movie_info(name)
                if not title:
                    continue
            
            self.add_torrent(
                source='TPB',
                title=title,
                year=year,
                name=name,
                info_hash=info_hash,
                seeders=int(item.get('seeders', 0)),
                leechers=int(item.get('leechers', 0)),
                size_bytes=int(item.get('size', 0)),
                imdb_id=item.get('imdb', '')
            )
    
    def finalize(self) -> List[Dict]:
        """
        Finalize aggregation:
        - Convert sets to lists
        - Sort torrents by quality tier then seeders
        - Return list of movies
        """
        quality_order = {'4K': 0, '1080p': 1, '720p': 2, '480p': 3, 'CAM': 4, 'TS': 5, 'TC': 6, 'Unknown': 7}
        
        result = []
        for key, movie in self.movies.items():
            # Convert sources set to sorted list
            movie['sources'] = sorted(list(movie['sources']))
            
            # Sort torrents: by quality tier, then by seeders (descending)
            movie['torrents'].sort(
                key=lambda t: (quality_order.get(t['quality'], 99), -t['seeders'])
            )
            
            result.append(movie)
        
        # Sort movies by first torrent's seeders (popularity)
        result.sort(key=lambda m: -m['torrents'][0]['seeders'] if m['torrents'] else 0)
        
        return result
    
    def to_json(self, indent: int = 2) -> str:
        """Export to JSON"""
        return json.dumps(self.finalize(), indent=indent)
    
    def stats(self) -> dict:
        """Get aggregation stats"""
        movies = self.finalize()
        return {
            'movies': len(movies),
            'torrents': sum(len(m['torrents']) for m in movies),
            'unique_hashes': len(self.seen_hashes),
            'sources': list(set(s for m in movies for s in m['sources']))
        }


if __name__ == '__main__':
    # Test the aggregator
    agg = UnifiedAggregator()
    
    # Add some test torrents
    agg.add_torrent('TPB', 'The Matrix', '1999', 'Matrix.1999.1080p.BluRay', 'ABC123DEF456', 1000, size_bytes=2*1024**3)
    agg.add_torrent('YTS', 'Matrix, The', '1999', 'Matrix.1999.720p.WEB', 'DEF456GHI789', 800, size_bytes=1024**3)
    agg.add_torrent('TPB', 'The Matrix', '1999', 'Matrix.1999.1080p.BluRay', 'ABC123DEF456', 1000)  # Duplicate!
    agg.add_torrent('TPB', 'The Matrix', '1999', 'Matrix.1999.4K.UHD', 'XYZ789ABC123', 500, size_bytes=8*1024**3)
    
    stats = agg.stats()
    print(f"✓ Aggregator test:")
    print(f"  Movies: {stats['movies']} (expected: 1)")
    print(f"  Torrents: {stats['torrents']} (expected: 3, duplicate removed)")
    print(f"  Sources: {stats['sources']}")
